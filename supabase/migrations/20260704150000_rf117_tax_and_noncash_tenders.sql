-- ============================================================================
-- RF-117 — taxes (per-branch setting) + non-cash tenders (card / Bit / external)
-- DECISIONS D-007 (integer minor money), D-011 (RPC-only sensitive mutation),
-- D-012 (rank + same-tenant), D-013 (append-only audit), D-023 (completed
-- payment terminal). MONEY_AND_TAX_SPEC §4/§5/§6/§9/§10/§14. RISK R-008.
-- ============================================================================
-- ADDITIVE + FORWARD-ONLY. It NEVER edits a prior migration. Two independent
-- pieces:
--
-- A. PER-BRANCH TAX SETTING (owner-controlled, default OFF; no hard-coded rate
--    because the jurisdiction is OPEN — Q-001/Q-002; MVP supports the shape,
--    ships no rate). Columns on branches: tax_enabled (default false),
--    tax_rate_bp (integer BASIS POINTS 0..10000, default 0), tax_mode
--    ('exclusive'|'inclusive', default 'exclusive' — this build WIRES exclusive
--    = tax added on top, which matches app.submit_order's existing grand
--    formula; inclusive is stored structurally for a follow-up). Three RPCs
--    mirror the RF-113 shift-close pattern EXACTLY: an owner write
--    (set_branch_tax), a member read (get_branch_tax), and a TOKEN-PROVEN POS
--    device read (get_device_branch_tax). The POS reads the rate to DISPLAY tax
--    and include tax_total_minor in the order it submits; app.submit_order keeps
--    its existing money validation (recomputes subtotal from snapshots, checks
--    grand = subtotal - discount + tax and grand >= 0). NOTE (honest): this
--    migration does NOT add server-side tax-RATE re-derivation inside
--    submit_order — that protected core RPC is intentionally left untouched, and
--    its pre-existing client-total trust for the tax/discount lines is unchanged
--    (subtotal, the real tampering vector, is already server-recomputed).
--    Server-authoritative tax-rate validation is a documented follow-up.
--
-- B. NON-CASH TENDERS. payments.method CHECK is extended from ('cash') to
--    ('cash','card','bit','external'), and app.record_payment (RF-054/RF-055) is
--    CREATE-OR-REPLACEd to accept them: cash keeps tendered>=total + change; a
--    non-cash tender records amount=grand_total, tendered=grand_total, change=0
--    (satisfies payments_change_balances) and stamps method = the real tender.
--    Everything else is preserved verbatim (PIN-session auth, open-shift + active
--    drawer precondition + stamping, order-bound idempotency, receipt numbering,
--    one-completed-payment-per-order, the two audits — now emitting the REAL
--    method). close_shift already sums ONLY method='cash' completed payments, so
--    card/Bit/external NEVER inflate expected cash (MONEY §14) — this is the core
--    RF-117 money-safety invariant and it holds by construction.
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual DOWN at the foot. RISK
-- R-003 human RLS/security sign-off still gates real tenant data (AGENTS.md).
-- ============================================================================

-- ############################################################################
-- A. PER-BRANCH TAX SETTING
-- ############################################################################

alter table public.branches
  add column tax_enabled boolean not null default false,
  add column tax_rate_bp integer not null default 0 check (tax_rate_bp between 0 and 10000),
  add column tax_mode    text    not null default 'exclusive' check (tax_mode in ('exclusive','inclusive'));

comment on column public.branches.tax_enabled is
  'RF-117: owner policy — whether this branch adds tax. Default false (no jurisdiction frozen; Q-001/Q-002). Written only by app.set_branch_tax (D-011).';
comment on column public.branches.tax_rate_bp is
  'RF-117: tax rate in integer BASIS POINTS (100 bp = 1.00%%; 0..10000). No float (D-007). Meaningful only when tax_enabled.';
comment on column public.branches.tax_mode is
  'RF-117: exclusive (tax added on top; WIRED) or inclusive (tax extracted from price; structural, follow-up). Default exclusive.';

-- ---------------------------------------------------------------------------
-- A1. OWNER write (mirrors app.set_branch_pos_shift_close_enabled / RF-113).
-- ---------------------------------------------------------------------------
create or replace function app.set_branch_tax(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid,
  p_enabled           boolean,
  p_rate_bp           integer
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor  uuid := app.current_app_user_id();
  v_rank   integer;
  v_fp     text;
  v_replay jsonb;
  v_result jsonb;
  v_old    jsonb;
  v_new    jsonb;
begin
  if v_actor is null then
    raise exception 'set_branch_tax: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'set_branch_tax: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    raise exception 'set_branch_tax: organization_id, restaurant_id and branch_id are required' using errcode = '42501';
  end if;
  if p_enabled is null then
    raise exception 'set_branch_tax: enabled is required' using errcode = '42501';
  end if;
  if p_rate_bp is null or p_rate_bp < 0 or p_rate_bp > 10000 then
    raise exception 'set_branch_tax: rate_bp must be an integer 0..10000 basis points' using errcode = '42501';
  end if;

  if not exists (select 1 from public.branches b
                 join public.restaurants r
                   on r.id = b.restaurant_id and r.organization_id = b.organization_id
                 where b.id = p_branch_id and b.organization_id = p_organization_id
                   and b.restaurant_id = p_restaurant_id
                   and b.deleted_at is null and r.deleted_at is null) then
    raise exception 'set_branch_tax: branch not found in organization/restaurant or scope is soft-deleted' using errcode = '42501';
  end if;

  v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id,
              'branch', p_branch_id, 'enabled', p_enabled, 'rate_bp', p_rate_bp)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'set_branch_tax', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  -- SAME gate as branch settings: rank >= restaurant_owner (managers/cashiers denied).
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'set_branch_tax: caller has no active membership covering the branch' using errcode = '42501';
  end if;
  if v_rank < 3 then
    perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id, 'settings.branch.update_denied', null,
      jsonb_build_object('branch_id', p_branch_id, 'setting', 'tax'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'branch');
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'branch',
                'branch_id', p_branch_id, 'tax_enabled', p_enabled, 'tax_rate_bp', p_rate_bp);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'set_branch_tax', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  select to_jsonb(t) into v_old from public.branches t where t.id = p_branch_id;
  update public.branches set tax_enabled = p_enabled, tax_rate_bp = p_rate_bp where id = p_branch_id;
  select to_jsonb(t) into v_new from public.branches t where t.id = p_branch_id;
  perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id, 'settings.branch.updated', v_old, v_new);
  return v_result;
end;
$$;

comment on function app.set_branch_tax(uuid, uuid, uuid, uuid, boolean, integer) is
  'RF-117 (D-011/D-012/D-013): OWNER write of the per-branch tax setting (enabled + rate_bp). Same auth/idempotency/audit/rank gate as app.set_branch_pos_shift_close_enabled — rank >= restaurant_owner; managers/cashiers DENIED. rate_bp is integer basis points 0..10000 (no float, D-007). tax_mode stays ''exclusive'' in this build.';

create or replace function public.set_branch_tax(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_enabled boolean, p_rate_bp integer)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.set_branch_tax(p_client_request_id, p_organization_id, p_restaurant_id, p_branch_id, p_enabled, p_rate_bp); $$;

revoke all on function app.set_branch_tax(uuid, uuid, uuid, uuid, boolean, integer)    from public;
grant execute on function app.set_branch_tax(uuid, uuid, uuid, uuid, boolean, integer) to authenticated;
revoke all on function public.set_branch_tax(uuid, uuid, uuid, uuid, boolean, integer)    from public;
grant execute on function public.set_branch_tax(uuid, uuid, uuid, uuid, boolean, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- A2. Dashboard READ (any active member covering the branch).
-- ---------------------------------------------------------------------------
create or replace function app.get_branch_tax(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid)
  returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_actor uuid := app.current_app_user_id();
  v_rank  integer;
  v_b     record;
begin
  if v_actor is null then
    raise exception 'get_branch_tax: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  select b.tax_enabled, b.tax_rate_bp, b.tax_mode into v_b
    from public.branches b
    where b.id = p_branch_id and b.organization_id = p_organization_id
      and b.restaurant_id = p_restaurant_id and b.deleted_at is null;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  return jsonb_build_object('ok', true, 'entity', 'branch', 'branch_id', p_branch_id,
                            'tax_enabled', v_b.tax_enabled, 'tax_rate_bp', v_b.tax_rate_bp, 'tax_mode', v_b.tax_mode);
end;
$$;

comment on function app.get_branch_tax(uuid, uuid, uuid) is
  'RF-117: Dashboard READ of the per-branch tax setting. Any active membership covering the branch (rank > 0); no membership / cross-tenant => not_found (no scope leak).';

create or replace function public.get_branch_tax(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.get_branch_tax(p_organization_id, p_restaurant_id, p_branch_id); $$;

revoke all on function app.get_branch_tax(uuid, uuid, uuid)    from public;
grant execute on function app.get_branch_tax(uuid, uuid, uuid) to authenticated;
revoke all on function public.get_branch_tax(uuid, uuid, uuid)    from public;
grant execute on function public.get_branch_tax(uuid, uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- A3. POS device READ (token-proven, mirrors app.get_device_pos_shift_close_enabled).
-- ---------------------------------------------------------------------------
create or replace function app.get_device_branch_tax(
  p_device_id uuid, p_session_token text)
  returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_hash text;
  v_b    record;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'branch_tax');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));
  select b.tax_enabled, b.tax_rate_bp, b.tax_mode into v_b
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    join public.devices d on d.id = ds.device_id
    join public.branches b on b.organization_id = ds.organization_id
      and b.restaurant_id = ds.restaurant_id and b.id = ds.branch_id and b.deleted_at is null
    join public.restaurants r on r.organization_id = ds.organization_id
      and r.id = ds.restaurant_id and r.deleted_at is null
    where ds.device_id = p_device_id
      and ds.session_token_ref = v_hash
      and ds.is_active and ds.revoked_at is null
      and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null
      and d.is_active and d.deleted_at is null;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'branch_tax');
  end if;
  return jsonb_build_object('ok', true, 'entity', 'branch_tax',
                            'tax_enabled', v_b.tax_enabled, 'tax_rate_bp', v_b.tax_rate_bp, 'tax_mode', v_b.tax_mode,
                            'server_ts', now());
end;
$$;

comment on function app.get_device_branch_tax(uuid, text) is
  'RF-117: TOKEN-PROVEN POS device read of its OWN branch tax setting (auth mirrors app.get_device_pos_shift_close_enabled; any failure => invalid_session, fail closed). Returns {ok, tax_enabled, tax_rate_bp, tax_mode}. No money, no secrets.';

create or replace function public.get_device_branch_tax(p_device_id uuid, p_session_token text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.get_device_branch_tax(p_device_id, p_session_token); $$;

revoke all on function app.get_device_branch_tax(uuid, text)    from public;
grant execute on function app.get_device_branch_tax(uuid, text) to authenticated;
revoke all on function public.get_device_branch_tax(uuid, text)    from public;
grant execute on function public.get_device_branch_tax(uuid, text) to authenticated;

-- ############################################################################
-- B. NON-CASH TENDERS
-- ############################################################################

-- B1. Extend the payments.method CHECK additively (RF-054 set was ('cash')).
alter table public.payments drop constraint payments_method_check;
alter table public.payments add  constraint payments_method_check
  check (method in ('cash','card','bit','external'));

comment on constraint payments_method_check on public.payments is
  'RF-117: tender methods = cash + non-cash externally-recorded tenders (card/bit/external). Non-cash are ''record external tender'' only — RestoFlow processes no card charge. close_shift sums ONLY method=''cash'' so non-cash never inflates expected cash (MONEY §14).';

-- B2. app.record_payment — accept non-cash tenders. CREATE OR REPLACE of the
--     RF-055 body; the ONLY changes are (d) the tender-set gate, (i) the
--     cash-vs-non-cash tender/change branch, (k) method = the real tender, and
--     (m) the audit method. Everything else is byte-for-byte the RF-055 body.
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
  v_tendered      bigint;          -- RF-117: effective tendered (cash: as given; non-cash: = payable)
  v_change        bigint;
  v_receipt_seq   bigint;
  v_receipt_no    text;
  v_payment_id    uuid;
  v_new_rev       integer;
  v_stored        jsonb;
  v_stored_order  uuid;
  v_result        jsonb;
  v_shift_id      uuid;
  v_drawer_id     uuid;
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

  -- (b) load the order; it MUST be in the actor's org + branch (no cross-tenant).
  --     RF-062 (A1): FOR UPDATE locks the order row FIRST (before the shift/drawer
  --     locks below), so record_payment and void_order serialize on the same order —
  --     a payment cannot complete between void_order's completed-payment guard and its
  --     void, and a void cannot complete between this check and the payment insert.
  --     Global lock order orders -> shifts -> drawer is preserved (no deadlock).
  select o.organization_id, o.branch_id, o.status, o.revision,
         o.grand_total_minor, o.currency_code, o.receipt_provisional_id
    into v_o_org, v_o_branch, v_o_status, v_o_rev, v_grand, v_currency, v_o_provisional
    from public.orders o where o.id = p_order_id
    for update;
  if not found then
    raise exception 'record_payment: order not found' using errcode = '42501';
  end if;
  if v_o_org <> v_org or v_o_branch <> v_branch then
    raise exception 'record_payment: order is not in the caller scope' using errcode = '42501';
  end if;

  -- (c) authorization (A7): cashier+ may record a payment. kitchen_staff/
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

  -- (d) safe input validation. RF-117: accept cash + non-cash externally-recorded tenders.
  if p_tender_type is null or p_tender_type not in ('cash', 'card', 'bit', 'external') then
    raise exception 'record_payment: unsupported tender type (got %)', coalesce(p_tender_type, '<null>') using errcode = '42501';
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

  -- (f2) RF-055 precondition + ROW LOCKS: an OPEN shift + ACTIVE bound cash drawer for
  --      (org, branch, device). Non-cash payments still record inside the shift (harmless:
  --      close_shift filters method='cash'), preserving the shift/drawer accounting model.
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

  -- (i) tender + change. payable = the order grand total (never recomputed). RF-117:
  --     CASH keeps physical tender >= payable with change = tendered - payable. A NON-CASH
  --     tender (card/bit/external) has no drawer cash movement: record the exact amount
  --     (tendered = payable, change = 0) so payments_change_balances holds and close_shift
  --     (method='cash' only) is unaffected. No cash rounding (MVP). No float (D-007).
  v_payable := v_grand;
  if p_tender_type = 'cash' then
    if p_amount_tendered_minor < v_payable then
      raise exception 'record_payment: amount_tendered_minor (%) is less than the order total (%)', p_amount_tendered_minor, v_payable using errcode = '42501';
    end if;
    v_tendered := p_amount_tendered_minor;
    v_change   := v_tendered - v_payable;
  else
    v_tendered := v_payable;
    v_change   := 0;
  end if;

  -- (j) allocate the authoritative per-branch receipt number (D-021) under a ROW LOCK.
  insert into public.branch_receipt_counters as brc
      (organization_id, restaurant_id, branch_id, last_issued_value)
    values (v_org, v_rest, v_branch, 1)
    on conflict (organization_id, restaurant_id, branch_id) do update
      set last_issued_value = brc.last_issued_value + 1
    returning brc.last_issued_value into v_receipt_seq;
  v_receipt_no := v_receipt_seq::text;

  -- (k) insert the completed payment, STAMPED with the open shift + active drawer.
  --     RF-117: method = the REAL tender type; non-cash tendered=payable/change=0.
  insert into public.payments (
    organization_id, restaurant_id, branch_id, order_id, device_id,
    taken_by_employee_profile_id, resolved_membership_id, shift_id, cash_drawer_session_id,
    method, status, amount_minor, tendered_minor, change_minor, currency_code,
    receipt_number, provisional_receipt_number, local_operation_id, revision)
  values (
    v_org, v_rest, v_branch, p_order_id, p_device_id,
    v_emp, v_membership, v_shift_id, v_drawer_id,
    p_tender_type, 'completed', v_payable, v_tendered, v_change, v_currency,
    v_receipt_no, p_provisional_receipt_number, p_local_operation_id, 1)
  returning id into v_payment_id;

  -- (l) set orders.receipt_number (+ keep any client provisional) and bump revision.
  v_new_rev := v_o_rev + 1;
  update public.orders
    set receipt_number = v_receipt_no,
        receipt_provisional_id = coalesce(v_o_provisional, p_provisional_receipt_number),
        revision = v_new_rev
    where id = p_order_id;

  -- (m) audit: payment.recorded (REAL method) + receipt_number.assigned (D-013).
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
      'method',                 p_tender_type,
      'status',                 'completed',
      'amount_minor',           v_payable,
      'tendered_minor',         v_tendered,
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
    'method', p_tender_type, 'receipt_number', v_receipt_no, 'change_due_minor', v_change,
    'shift_id', v_shift_id, 'cash_drawer_session_id', v_drawer_id,
    'payment_revision', 1, 'order_revision', v_new_rev);
  insert into public.order_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, order_id, result)
    values (v_org, v_rest, v_branch, p_device_id, p_local_operation_id, 'record_payment', p_order_id, v_result);
  return v_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.record_payment(uuid, uuid, uuid, text, text, bigint, text, integer) is
  'RF-054/RF-055/RF-117 (API_CONTRACT §4.7, D-011) SECURITY DEFINER RPC: records a payment + assigns the per-branch receipt number (D-021). RF-117: accepts tender cash|card|bit|external. CASH keeps tendered>=grand_total + change=tendered-grand_total; NON-CASH (externally-recorded card/Bit/other) records amount=tendered=grand_total, change=0 — RestoFlow processes no card charge. Requires an open shift + active bound cash drawer (precondition_failed 42501) and stamps shift_id/cash_drawer_session_id; close_shift sums ONLY method=cash so non-cash never inflates expected cash (MONEY §14). PIN-session auth (cross-tenant impossible); cashier+ only (kitchen_staff/accountant denied -> payment.denied + permission_denied); order-bound idempotency; at most one completed payment per order; does NOT advance orders.status (D-025); writes payment.recorded (REAL method) + receipt_number.assigned (D-013). completed is TERMINAL (D-023).';

revoke all on function app.record_payment(uuid, uuid, uuid, text, text, bigint, text, integer) from public;
grant execute on function app.record_payment(uuid, uuid, uuid, text, text, bigint, text, integer) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase forward-only — `supabase db reset` replays):
--   -- restore the RF-055 record_payment (cash-only) by re-running its CREATE OR REPLACE.
--   alter table public.payments drop constraint payments_method_check;
--   alter table public.payments add  constraint payments_method_check check (method in ('cash'));
--   drop function if exists public.get_device_branch_tax(uuid, text);
--   drop function if exists app.get_device_branch_tax(uuid, text);
--   drop function if exists public.get_branch_tax(uuid, uuid, uuid);
--   drop function if exists app.get_branch_tax(uuid, uuid, uuid);
--   drop function if exists public.set_branch_tax(uuid, uuid, uuid, uuid, boolean, integer);
--   drop function if exists app.set_branch_tax(uuid, uuid, uuid, uuid, boolean, integer);
--   alter table public.branches drop column if exists tax_mode, drop column if exists tax_rate_bp, drop column if exists tax_enabled;
-- ============================================================================
