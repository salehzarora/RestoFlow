-- ============================================================================
-- RF-054 — payments + branch_receipt_counters + app.record_payment (cash) RPC
-- ============================================================================
-- The cash payment WRITE path + authoritative per-branch receipt numbering.
-- Builds on RF-014 (org/restaurant/branch core + app.current_org_id/has_scope/
-- set_updated_at), RF-015 (memberships/employee_profiles), RF-016/051 (PIN session
-- + app.is_pin_session_valid), RF-017 (append-only audit_events), RF-052 (orders +
-- app.order_parse_minor), RF-053 (the order_operations idempotency ledger).
-- Additive and FORWARD-ONLY: it NEVER edits a prior migration.
--
-- WHAT THIS DOES (API_CONTRACT §4.7 record_payment + assign_receipt_number)
--   1. branch_receipt_counters — a per-branch monotonic receipt-number allocator
--      (D-021). Server-side only; allocated under a row lock inside the RPC so
--      concurrent payments in the same branch get unique, gapless, monotonic
--      numbers, and a rolled-back payment does NOT permanently consume a number.
--   2. payments — a cash payment row (tenant+branch scoped, integer _minor money
--      only, D-007). Direct INSERT/UPDATE/DELETE revoked from authenticated; the
--      SECURITY DEFINER RPC is the only writer (D-011).
--   3. A per-branch UNIQUE index on orders.receipt_number (numbering = RF-054;
--      RF-052 left it NULL) so a receipt number is unique within a branch.
--   4. order_operations.action CHECK extended additively to include
--      'record_payment' (reuses the RF-053 idempotency ledger; A5).
--   5. app.record_payment(...) SECURITY DEFINER RPC: authorizes the caller via a
--      VALID PIN SESSION (actor + scope derived server-side, never from the
--      client), validates the cash tender, allocates the authoritative receipt
--      number, records a completed cash payment, computes integer change_due, sets
--      orders.receipt_number (NOT orders.status — D-025), and writes two append-only
--      audit rows. Idempotent on (device_id, local_operation_id) via order_operations.
--
-- DECISIONS
--   * D-007 integer minor money; NO float/numeric/double/money types for money.
--   * D-011 sensitive mutations only via SECURITY DEFINER RPC; clients never write
--     tenant rows directly; no service-role in clients.
--   * D-012 four layers; composite same-org FKs (layer 4).
--   * D-013 append-only audit (success: payment.recorded + receipt_number.assigned;
--     denial: payment.denied). D-022 idempotency key = device_id + local_operation_id.
--   * D-021 receipt number = per-branch server-assigned monotonic sequence; offline
--     provisional id reconciled to the authoritative number on sync.
--   * D-023 a completed payment is TERMINAL (no void/refund/reversal in MVP).
--   * D-025 payment and fulfillment are INDEPENDENT: recording a payment does NOT
--     auto-advance orders.status (pay-first is supported).
--   * RF053-B1 lesson: idempotency replay happens ONLY after authorization + safe
--     input validation, and is ORDER-BOUND (same key on a different order = conflict).
--
-- APPROVED INTERIM DECISIONS (RF-054; human-approved A1..A8)
--   * A1: branch_receipt_counters is additive (not in the frozen DOMAIN_MODEL, which
--     leaves the sequence MECHANICS to MONEY_AND_TAX_SPEC). Server-side only; row-lock
--     allocation; per-branch monotonic + unique; rollback-safe.
--   * A2: payments.shift_id / cash_drawer_session_id are nullable, NON-FK uuids — no
--     backend shifts/cash_drawer_sessions tables exist (RF-055). The contract's "open
--     shift + active cash drawer" precondition is therefore N/A until RF-055.
--   * A3: no void_payment RPC (payment void/refund/reversal DEFERRED, D-023). The
--     status CHECK carries the proposed forward-compatible values; this RPC only ever
--     produces 'completed' (cash settles immediately).
--   * A4: Q-004 legal receipt format/reset is OPEN. Interim authoritative receipt
--     number = the bare per-branch monotonic integer as text ('1','2','3',...). No
--     prefix, no annual reset, no legal formatting, no printing/rendering.
--   * A5: extend order_operations.action additively here (do NOT edit RF-053);
--     void_order/apply_discount behavior preserved.
--   * A6: record_payment does NOT change orders.status (D-025); it sets the receipt
--     number and bumps the order revision. Fulfillment/order completion is not RF-054.
--   * A7: an unauthorized payment writes a payment.denied audit + returns
--     permission_denied (no raise, so the audit persists), with NO payment, NO receipt
--     number, NO order mutation, NO ledger write.
--   * A8: a successful payment writes exactly two audit rows (payment.recorded +
--     receipt_number.assigned); a replay returns before the audit step (no duplicates).
--
-- OUT OF SCOPE: void_payment / refunds / completed-payment reversal (D-023); card /
--   online tenders; tips (Q-011); service charge (Q-012); cash rounding (Q-001/Q-002);
--   partial/split tender; legal receipt format/reset (Q-004); RF-055 shift/cash-drawer
--   reconciliation; RF-056/057 sync/outbox; order -> completed fulfillment advance
--   (D-025); printing/receipt rendering; reports; route_to_kitchen + kitchen tables;
--   RF-059 full role matrix; any UI / Dart / config / remote / secrets / service-role.
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. branch_receipt_counters — per-branch monotonic receipt-number allocator
--    (D-021). One row per (organization_id, restaurant_id, branch_id). Tenant +
--    branch scoped; cross-org/branch refs are structurally impossible via the
--    composite same-org FK (D-012 layer 4). Written ONLY by app.record_payment
--    (SECURITY DEFINER); authenticated gets SELECT only.
--
--    SEMANTICS (documented + tested): last_issued_value is the most recently
--    ISSUED receipt number for the branch; 0 = none issued yet. The NEXT receipt
--    number is (last_issued_value + 1). Allocation is a single atomic
--    INSERT ... ON CONFLICT DO UPDATE SET last_issued_value = last_issued_value + 1
--    RETURNING last_issued_value, which takes a ROW LOCK on the counter row so
--    concurrent allocators in the same branch serialize (unique + gapless +
--    monotonic). Because the increment lives in the payment transaction, a
--    ROLLBACK un-does it — a failed payment never permanently consumes a number.
-- ----------------------------------------------------------------------------
create table branch_receipt_counters (
  id                uuid        not null default gen_random_uuid(),
  organization_id   uuid        not null references organizations (id) on delete restrict,
  restaurant_id     uuid        not null,
  branch_id         uuid        not null,
  last_issued_value bigint      not null default 0 check (last_issued_value >= 0),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  primary key (id),
  unique (organization_id, restaurant_id, branch_id),               -- one counter per branch (the ON CONFLICT target)
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict
);

comment on table branch_receipt_counters is
  'RF-054: per-branch monotonic receipt-number allocator (D-021). last_issued_value = the most recently issued receipt number (0 = none yet); the next number is last_issued_value + 1, allocated under a row lock inside app.record_payment (unique + gapless + monotonic per branch; rollback-safe). Written ONLY by the SECURITY DEFINER RPC; authenticated SELECT-only.';
comment on column branch_receipt_counters.last_issued_value is
  'RF-054: the most recently ISSUED per-branch receipt number (0 = none issued yet). Next = last_issued_value + 1.';

create index branch_receipt_counters_branch_idx on branch_receipt_counters (organization_id, restaurant_id, branch_id);

create trigger branch_receipt_counters_set_updated_at
  before update on branch_receipt_counters for each row execute function app.set_updated_at();

alter table branch_receipt_counters enable row level security;
alter table branch_receipt_counters force  row level security;

create policy branch_receipt_counters_scoped on branch_receipt_counters
  for all to authenticated
  using      (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id))
  with check (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));

grant select on branch_receipt_counters to authenticated;
revoke insert, update, delete on branch_receipt_counters from authenticated;

-- ----------------------------------------------------------------------------
-- 2. payments — a cash payment against an order. Tenant+branch scoped; all money
--    integer _minor (bigint; D-007). Idempotency key (device_id, local_operation_id).
--    Composite same-org FKs to the backend tables that exist; shift/cash-drawer are
--    NON-FK nullable uuids (no backend table; A2). Written ONLY by app.record_payment.
-- ----------------------------------------------------------------------------
create table payments (
  id                           uuid        not null default gen_random_uuid(),
  organization_id              uuid        not null references organizations (id) on delete restrict,
  restaurant_id                uuid        not null,
  branch_id                    uuid        not null,
  order_id                     uuid        not null,
  device_id                    uuid        not null,
  taken_by_employee_profile_id uuid        not null,
  resolved_membership_id       uuid        not null,
  shift_id                     uuid,                          -- non-FK reference (no backend shifts table; A2)
  cash_drawer_session_id       uuid,                          -- non-FK reference (no backend cash_drawer_sessions table; A2)
  method                       text        not null check (method in ('cash')),                       -- card/online DEFERRED
  status                       text        not null
                                 check (status in ('pending','tendered','completed','voided','failed')),  -- proposed set (D-018); refunded DEFERRED; RF-054 only produces 'completed'
  amount_minor                 bigint      not null check (amount_minor   >= 0),  -- amount applied to the order (= order grand total)
  tendered_minor               bigint      not null check (tendered_minor >= 0),  -- cash handed over
  change_minor                 bigint      not null check (change_minor   >= 0),  -- tendered - amount (never negative)
  currency_code                text        not null check (currency_code ~ '^[A-Z]{3}$'),
  receipt_number               text,                          -- authoritative per-branch number assigned with this payment
  provisional_receipt_number   text,                          -- optional client offline provisional id (reconciliation record)
  local_operation_id           text        not null,
  revision                     integer     not null default 1,
  created_at                   timestamptz not null default now(),
  updated_at                   timestamptz not null default now(),
  deleted_at                   timestamptz,
  primary key (id),
  unique (organization_id, id),                               -- same-org composite-FK target (forward-compat)
  unique (device_id, local_operation_id),                     -- idempotency (D-022) race backstop
  -- a completed cash payment must be fully tendered (tendered covers the amount, change is the difference)
  constraint payments_change_balances check (change_minor = tendered_minor - amount_minor),
  foreign key (organization_id, order_id)
    references orders (organization_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id, device_id)
    references devices (organization_id, restaurant_id, branch_id, id) on delete restrict,
  foreign key (organization_id, taken_by_employee_profile_id)
    references employee_profiles (organization_id, id) on delete restrict,
  foreign key (organization_id, resolved_membership_id)
    references memberships (organization_id, id) on delete restrict
);

comment on table payments is
  'RF-054: a cash payment against an order (API_CONTRACT §4.7). Tenant+branch scoped; all money integer _minor (D-007). Written ONLY by app.record_payment (SECURITY DEFINER; D-011). status carries the proposed set (D-018); RF-054 settles cash immediately to ''completed'' (TERMINAL, D-023; void/refund DEFERRED). shift_id/cash_drawer_session_id are non-FK uuids (no backend table; A2). change_minor = tendered_minor - amount_minor (never negative).';

create index payments_order_idx      on payments (organization_id, order_id);
create index payments_branch_idx     on payments (organization_id, restaurant_id, branch_id);
create index payments_device_idx     on payments (organization_id, restaurant_id, branch_id, device_id);
create index payments_employee_idx   on payments (organization_id, taken_by_employee_profile_id);
create index payments_membership_idx on payments (organization_id, resolved_membership_id);
-- one COMPLETED payment per order (D-024/D-025: an order is paid at most once in MVP)
create unique index payments_one_completed_per_order_uidx
  on payments (organization_id, order_id) where status = 'completed';

create trigger payments_set_updated_at
  before update on payments for each row execute function app.set_updated_at();

alter table payments enable row level security;
alter table payments force  row level security;

create policy payments_scoped on payments
  for all to authenticated
  using      (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id))
  with check (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));

grant select on payments to authenticated;
revoke insert, update, delete on payments from authenticated;

-- ----------------------------------------------------------------------------
-- 3. Per-branch UNIQUE receipt index on orders. RF-052 left receipt_number NULL
--    ("numbering = RF-054"). A partial unique index makes a duplicate receipt
--    number within a branch impossible while leaving unpaid orders (NULL) free.
-- ----------------------------------------------------------------------------
create unique index orders_branch_receipt_number_uidx
  on orders (organization_id, restaurant_id, branch_id, receipt_number)
  where receipt_number is not null;

comment on index orders_branch_receipt_number_uidx is
  'RF-054: a receipt number is unique within (organization_id, restaurant_id, branch_id). Partial (WHERE receipt_number IS NOT NULL) so unpaid orders are unconstrained (D-021).';

-- ----------------------------------------------------------------------------
-- 4. Extend order_operations.action additively to include 'record_payment'
--    (A5; reuse the RF-053 ledger). Drop + recreate the inline CHECK in THIS
--    migration (the RF-053 file is unchanged). void_order/apply_discount preserved.
-- ----------------------------------------------------------------------------
alter table public.order_operations drop constraint order_operations_action_check;
alter table public.order_operations add  constraint order_operations_action_check
  check (action in ('void_order', 'apply_discount', 'record_payment'));

comment on constraint order_operations_action_check on public.order_operations is
  'RF-054: extends the RF-053 action set with record_payment (A5). void_order/apply_discount preserved.';

-- ----------------------------------------------------------------------------
-- 5. app.record_payment — the API_CONTRACT §4.7 SECURITY DEFINER RPC.
--    Validation order (RF051-B1 / RF053-B1): PIN session -> backing device session/
--    pairing -> device match -> membership active/role -> load order in scope ->
--    authorization (denied = audit + return, no raise) -> safe input validation ->
--    ONLY THEN idempotency replay (order-bound) -> state legality + no-existing-
--    completed-payment -> tender/change -> allocate receipt number (row lock) ->
--    insert completed payment -> set orders.receipt_number (NOT status) + bump
--    revision -> two audit rows -> ledger. Actor + org/restaurant/branch derived
--    from the PIN session, never trusted from the client.
-- ----------------------------------------------------------------------------
create or replace function app.record_payment(
  p_pin_session_id             uuid,
  p_order_id                   uuid,
  p_device_id                  uuid,
  p_local_operation_id         text,
  p_tender_type                text,        -- 'cash' (only cash in RF-054)
  p_amount_tendered_minor      bigint,      -- integer minor units (bigint => no float can enter; D-007)
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

  -- (c) authorization (A7): cashier+ (cashier/manager/restaurant_owner/org_owner) may
  --     record a cash payment (no special permission grant required, unlike void).
  --     kitchen_staff/accountant/other roles are denied. RF053-B1: authorization runs
  --     BEFORE the idempotency replay so an unauthorized actor can never replay a prior
  --     SUCCESS. A DENIAL is audited (payment.denied) + RETURNED (no raise, so the audit
  --     persists) with NO payment, NO receipt number, NO order mutation, NO ledger write.
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

  -- (d) safe input validation (operation shape; independent of mutable post-success state)
  if p_tender_type is null or p_tender_type <> 'cash' then
    raise exception 'record_payment: only cash tender is supported (got %)', coalesce(p_tender_type, '<null>') using errcode = '42501';
  end if;
  if p_amount_tendered_minor is null or p_amount_tendered_minor < 0 then
    raise exception 'record_payment: amount_tendered_minor must be a non-negative integer (minor units)' using errcode = '42501';
  end if;

  -- (e) idempotency replay (RF053-B1): AFTER authorization + input validation,
  --     ORDER-BOUND. Same (org, device, local_operation_id, action='record_payment')
  --     on a DIFFERENT order is a conflict, not a replay (never leaks/double-allocates).
  --     A replay returns the stored result verbatim (same payment_id + same authoritative
  --     receipt_number; no second allocation, no duplicate payment, no duplicate audit).
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

  -- (f) eligible order states (D-025): pay-first supported; payment is independent of
  --     fulfillment. draft/cancelled/voided/completed are excluded.
  if v_o_status not in ('submitted', 'accepted', 'preparing', 'ready', 'served') then
    raise exception 'record_payment: order status % is not a legal payment source state', v_o_status using errcode = '42501';
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

  -- (i) tender + change. payable = the order grand total (already computed; never
  --     recomputed here). No cash rounding in MVP (Q-001/Q-002). A single full cash
  --     tender must cover the payable; change is the non-negative difference.
  v_payable := v_grand;
  if p_amount_tendered_minor < v_payable then
    raise exception 'record_payment: amount_tendered_minor (%) is less than the order total (%)', p_amount_tendered_minor, v_payable using errcode = '42501';
  end if;
  v_change := p_amount_tendered_minor - v_payable;

  -- (j) allocate the authoritative per-branch receipt number (D-021) under a ROW
  --     LOCK (unique + gapless + monotonic; rollback-safe — see the table comment).
  insert into public.branch_receipt_counters as brc
      (organization_id, restaurant_id, branch_id, last_issued_value)
    values (v_org, v_rest, v_branch, 1)
    on conflict (organization_id, restaurant_id, branch_id) do update
      set last_issued_value = brc.last_issued_value + 1
    returning brc.last_issued_value into v_receipt_seq;
  v_receipt_no := v_receipt_seq::text;   -- interim bare integer as text (A4; legal format = Q-004)

  -- (k) insert the completed cash payment
  insert into public.payments (
    organization_id, restaurant_id, branch_id, order_id, device_id,
    taken_by_employee_profile_id, resolved_membership_id, shift_id, cash_drawer_session_id,
    method, status, amount_minor, tendered_minor, change_minor, currency_code,
    receipt_number, provisional_receipt_number, local_operation_id, revision)
  values (
    v_org, v_rest, v_branch, p_order_id, p_device_id,
    v_emp, v_membership, null, null,
    'cash', 'completed', v_payable, p_amount_tendered_minor, v_change, v_currency,
    v_receipt_no, p_provisional_receipt_number, p_local_operation_id, 1)
  returning id into v_payment_id;

  -- (l) set orders.receipt_number (+ keep any client provisional) and bump revision.
  --     DOES NOT change orders.status (D-025; A6).
  v_new_rev := v_o_rev + 1;
  update public.orders
    set receipt_number = v_receipt_no,
        receipt_provisional_id = coalesce(v_o_provisional, p_provisional_receipt_number),
        revision = v_new_rev
    where id = p_order_id;

  -- (m) audit: payment.recorded + receipt_number.assigned (A8; D-013). actor =
  --     employee_profile (RF-017 requires app_user OR employee_profile present). The
  --     replay path returns earlier, so a replay writes NEITHER row a second time.
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
    'payment_revision', 1, 'order_revision', v_new_rev);
  insert into public.order_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, order_id, result)
    values (v_org, v_rest, v_branch, p_device_id, p_local_operation_id, 'record_payment', p_order_id, v_result);
  return v_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.record_payment(uuid, uuid, uuid, text, text, bigint, text, integer) is
  'RF-054 (API_CONTRACT §4.7, D-011) SECURITY DEFINER RPC: records a cash payment + assigns the authoritative per-branch receipt number (D-021). Actor/org/restaurant/branch from a VALID PIN session (cross-tenant impossible). Authorized for cashier/manager/restaurant_owner/org_owner; kitchen_staff/accountant/other denied -> payment.denied audit + returned permission_denied (no raise), NO state change (A7). cash only; amount_tendered must cover the order grand total; change_due_minor = tendered - total (integer, never negative; D-007). Eligible order states submitted/accepted/preparing/ready/served (draft/cancelled/voided/completed rejected; D-025); at most one completed payment per order. Does NOT advance orders.status (D-025; A6); sets orders.receipt_number + bumps revision. Receipt number = per-branch monotonic integer allocated under a row lock (unique/gapless/rollback-safe). Idempotent via order_operations (D-022, order-bound; replay returns the same payment_id + receipt_number, no duplicate audit). Writes payment.recorded + receipt_number.assigned (A8/D-013). completed is TERMINAL (D-023); void/refund DEFERRED.';

revoke all on function app.record_payment(uuid, uuid, uuid, text, text, bigint, text, integer) from public;
grant execute on function app.record_payment(uuid, uuid, uuid, text, text, bigint, text, integer) to authenticated;

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; cleanliness gate is
-- `supabase db reset`. Reverse-dependency teardown:
-- ----------------------------------------------------------------------------
-- drop function if exists app.record_payment(uuid, uuid, uuid, text, text, bigint, text, integer);
-- alter table public.order_operations drop constraint order_operations_action_check;
-- alter table public.order_operations add  constraint order_operations_action_check
--   check (action in ('void_order', 'apply_discount'));   -- restore the RF-053 set
-- drop index if exists public.orders_branch_receipt_number_uidx;
-- drop table if exists payments;
-- drop table if exists branch_receipt_counters;
-- ============================================================================
