-- ============================================================================
-- ORDER-AUTO-COMPLETION-001 — a served order that is FULLY PAID completes itself.
--
-- THE RULE (new normal): served + fully settled => completed, automatically, in
-- the SAME transaction as the operation that made it true. An operator must not
-- have to close every ordinary order by hand. An UNPAID served order stays ACTIVE
-- in Awaiting close — it is a real exception and must remain visible.
--
-- TWO TRIGGER DIRECTIONS, ONE SHARED DECISION HELPER:
--   A. the order reaches `served` and is ALREADY fully paid
--      -> chained at the tail of app.apply_order_status_transition (the KDS bump).
--   B. the order is ALREADY `served` and BECOMES fully paid
--      -> chained at the tail of app.record_payment (a POS payment / "pay later").
-- Both callers ALREADY hold the order row lock (`select ... for update` is the
-- FIRST lock both take), so the completion is written under that same lock, in
-- the same transaction, with NO new lock and NO new lock order. There is no
-- polling job, no scheduled worker, and no second state machine.
--
-- ------------------------------------------------------------------ THE GATE --
-- THE PAYMENT INVARIANT WAS VERIFIED BEFORE WRITING A LINE OF THIS:
--   * app.record_payment is the ONLY writer of public.payments in the whole tree
--     (4 INSERTs, all inside its own stacked definitions; ZERO UPDATE, ZERO DELETE
--     anywhere), so a `pending` row can never be flipped to `completed` later.
--   * Direct DML on payments is REVOKEd from `authenticated` (RF-054) and denied by
--     explicit `with check (false)` RLS policies with RLS ENABLE + FORCE (RF-059);
--     `anon` matches no policy at all. There is no public.record_payment wrapper —
--     the only client route is sync_push -> PIN-session + active-pairing + cashier+.
--   * record_payment takes NO amount parameter. The stored amount is FORCED to the
--     order's own total: `v_payable := v_grand;` and the row is inserted with the
--     literal status 'completed' (RF-117). Partial payment has no code path.
--   * At most ONE completed payment per order, enforced twice: the partial unique
--     index payments_one_completed_per_order_uidx AND an in-function guard.
--
-- ...BUT the marker is NOT time-invariant, and this ticket must not trust a marker:
--   app.apply_discount REPLACES the discount and RECOMPUTES orders.grand_total_minor,
--   guarded only by terminal status. Because record_payment deliberately does NOT
--   advance orders.status (D-025), a fully-paid order is still non-terminal and
--   therefore still discountable — so a SECOND, SMALLER discount can raise
--   grand_total_minor back ABOVE the already-frozen payments.amount_minor. The
--   payment row is never falsified; the TARGET moves under it.
--
--   The ticket forbids auto-completing on an unreliable "any completed payment
--   exists" test — so we do not. app.order_is_fully_settled compares INTEGER MINOR
--   UNITS: `payments.amount_minor >= orders.grand_total_minor`. That is a true
--   SETTLEMENT test rather than a marker test, it is identical to the old exists()
--   in every normal case (the amount IS the total), and it blocks no legitimate
--   completion. The same predicate now also hardens the D-025 gate on the MANUAL
--   path (ORDER-COMPLETION-001), which previously trusted the bare marker.
--
--   FOLLOW-UP (out of scope here — this is the money domain and the ticket forbids
--   discount changes): MONEY-DISCOUNT-GUARD-001 — app.apply_discount should refuse
--   an order that already carries a live completed payment (mirroring the guard
--   app.void_order already has) and should lock the order row FOR UPDATE. Note that
--   auto-completion SHRINKS that window rather than widening it: once the order is
--   `completed` it is terminal, and apply_discount already refuses a terminal order.
--
-- ------------------------------------------------------- AUTHORIZATION / ACTOR --
-- The automatic step does NOT re-run the role gate, and that is deliberate and
-- correct: authorization already happened on the TRIGGERING operation (the KDS bump
-- was authorized; the payment was authorized). Auto-completion is a SYSTEM RULE
-- consequence of that authorized act, not a second human decision.
--
-- This matters concretely: the core DENIES kitchen_staff -> completed and AUDITS the
-- denial. Direction A's initiating actor IS kitchen_staff (the KDS bump). Naively
-- re-entering the role-gated core would emit a spurious `order.status_update_denied`
-- on EVERY KDS bump of a paid order and complete nothing. So the automatic step is a
-- separate internal helper that never consults the role gate. The MANUAL, explicitly
-- human-initiated paths (app.update_order_status / app.owner_complete_order) keep the
-- frozen role gate exactly as it is — it is NOT weakened.
--
-- The audit event names the REAL initiating actor and device (no invented "system"
-- principal — there is no such concept in audit_events, and a NULL actor renders as
-- "unknown", which would be actively misleading), plus completion_mode='automatic'
-- and the trigger that caused it.
--
-- ----------------------------------------------------------------- AUDIT SHAPE --
-- NO new action key. The canonical `order.status_updated` already classifies as
-- ORDERS (never "Other") and already carries a safe payload projection, so it is
-- reused and given two new SAFE scalar fields:
--     completion_mode    'automatic' | 'manual'
--     completion_trigger 'order_served' | 'payment_recorded'   (automatic only)
-- app.audit_safe_detail's allowlist gains exactly those two keys. Still money-free
-- (T-003): no *_minor value is written by this path.
--
-- A paid order bumped by the KDS therefore produces TWO audit events, which is the
-- honest record of TWO real transitions: `ready -> served` (actor: the kitchen) and
-- `served -> completed` (mode: automatic, trigger: order_served). We do NOT collapse
-- them — the served step genuinely happened and the kitchen genuinely did it.
--
-- ----------------------------------------------------------------- SIDE EFFECTS --
-- orders.status + orders.revision only (+ updated_at via the RF-052 trigger) and ONE
-- audit row. NO payment is created, NO payment row is touched, no total is
-- recomputed, no table is freed, no shift/drawer/receipt changes. NO reported MONEY
-- figure moves: every money aggregate is derived from payments.status='completed' and
-- filters orders only by the negative set, so `served` and `completed` are already
-- treated identically. Only the non-money completed_count/open_count move — which is
-- a correctness FIX, because nothing writes `completed` in the field today.
--
-- Additive / forward-only. No table, column, CHECK, RLS policy, trigger or index
-- change; no historical order, payment or audit row is rewritten; no lifecycle
-- transition is added (the legality CASE is untouched — direction A CHAINS a second
-- legal single-step transition under the same lock, it does not widen the table).
-- PENDING: RISK R-003 sign-off. NOT applied to hosted by this migration.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. app.order_is_fully_settled — THE ONE authoritative settlement test.
--
--    It answers ONE question — "does this order still owe money?" — and it is the
--    SINGLE definition used by BOTH the automatic paths AND the D-025 gate on the
--    manual path. There is no second predicate and no zero-total special case
--    anywhere else in the system (not in the RPCs, not in the client).
--
--    THE RULE (authoritative):
--      grand_total_minor  = 0  -> SETTLED. A zero-total order is NON-CHARGEABLE: it
--                                owes nothing, so it is settled WITHOUT a payment row,
--                                and NEITHER the automatic rule NOR the manual
--                                completion ever creates one for it. (Precisely: no
--                                COMPLETION path writes a payment. app.record_payment
--                                remains willing to record an explicit 0-amount
--                                payment if a cashier taps "take payment" on a comped
--                                order — that is a cashier-initiated act, unchanged by
--                                this ticket, and it is NOT how the order settles.
--                                See MONEY-ZERO-TENDER-GUARD-001 in the docs.)
--      grand_total_minor  > 0  -> CHARGEABLE. Settled ONLY when a LIVE COMPLETED
--                                payment COVERS the CURRENT total, in INTEGER MINOR
--                                UNITS (D-007). D-025 is NOT weakened.
--      grand_total_minor  < 0  -> FAIL CLOSED (not settled). Unreachable today (the
--                                orders CHECK is grand_total_minor >= 0), but a
--                                negative total would be a money defect and must
--                                never silently close an order.
--      missing / soft-deleted / cross-tenant order -> FAIL CLOSED (not settled).
--
--    A SETTLEMENT test, not a MARKER test. The naive `exists(a completed payment)`
--    is wrong in BOTH directions:
--      * false NEGATIVE — it never settles a zero-total order (no payment row exists
--        to find), which left a comped / 100%-discounted order stuck in Awaiting
--        close forever: the automatic rule would not close it AND the manual
--        recovery RPC refused it with `order_not_paid`, because both consult this
--        same predicate. That was a real defect, fixed here.
--      * false POSITIVE — app.apply_discount RE-BASES grand_total_minor after a
--        payment is taken (it is guarded only by terminal status, and a paid order is
--        deliberately still non-terminal per D-025), so a later, smaller discount can
--        raise the total back ABOVE the already-frozen payments.amount_minor. The
--        payment row is never falsified; the TARGET moves under it. Hence the
--        amount-aware `>=` comparison rather than a bare existence check.
--        (Follow-up: MONEY-DISCOUNT-GUARD-001.)
-- ---------------------------------------------------------------------------
create or replace function app.order_is_fully_settled(
  p_organization_id uuid,
  p_order_id        uuid
)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  -- The scan starts at the ORDER, not at payments: a zero-total order HAS no payment
  -- row, so a payments-rooted query could never see it. coalesce(...) makes a missing
  -- / deleted / out-of-tenant order FAIL CLOSED as `false` rather than NULL, so no
  -- caller can trip on three-valued logic.
  select coalesce((
    select case
             when o.grand_total_minor < 0 then false            -- fail closed
             when o.grand_total_minor = 0 then true             -- NON-CHARGEABLE
             else exists (                                      -- CHARGEABLE (D-025)
               select 1
               from public.payments p
               where p.organization_id = o.organization_id
                 and p.order_id        = o.id
                 and p.deleted_at is null
                 and p.status          = 'completed'
                 -- INTEGER minor units only (D-007). Never a float, never a client
                 -- number. `>=` COVERS the total; it does not merely exist.
                 and p.amount_minor   >= o.grand_total_minor
             )
           end
    from public.orders o
    where o.id              = p_order_id
      and o.organization_id = p_organization_id
      and o.deleted_at is null
  ), false);
$$;

comment on function app.order_is_fully_settled(uuid, uuid) is
  'ORDER-AUTO-COMPLETION-001 (D-007/D-025): the ONE authoritative "does this order still owe money?" test, used by BOTH the automatic completion paths AND the D-025 gate on the manual path — there is exactly one definition of settled, and no zero-total special case exists anywhere else. RULE: grand_total_minor = 0 -> SETTLED (a zero-total order is NON-CHARGEABLE: it owes nothing and settles with NO payment row; no COMPLETION path ever creates one for it); grand_total_minor > 0 -> settled ONLY when a live completed payment COVERS the CURRENT total in integer minor units (D-025 is not weakened); grand_total_minor < 0, or a missing/soft-deleted/cross-tenant order -> FAIL CLOSED. This is a SETTLEMENT test, not a MARKER test: a bare exists()-a-completed-payment check is wrong in both directions — it can never settle a zero-total order (no payment row exists to find, which left comped orders permanently stuck), and app.apply_discount can re-base grand_total_minor after payment, so it could report a part-settled order as paid. A completion of a zero-total order audits payment_status=not_chargeable, never the false literal "paid". INTERNAL: granted to no client role.';

-- ---------------------------------------------------------------------------
-- 2. app.try_auto_complete_order — the ONE automatic decision, shared by both
--    trigger directions.
--
--    CONTRACT (read this before changing it):
--      * The caller MUST already hold the order row lock (both callers take
--        `select ... for update` on orders as their FIRST lock). This helper adds
--        NO new lock, so it cannot introduce a lock-order inversion or a deadlock.
--      * It NEVER RAISES. A failure here must never turn a SUCCESSFUL payment into a
--        client-side failure — the POS payment parser is fail-closed and treats any
--        non-`applied` result as a failed payment. Auto-completion is a consequence
--        of the operation, never a precondition of it.
--      * It does NOT re-run the role gate: authorization already passed on the
--        triggering operation (see the header).
--      * It is IDEMPOTENT and single-shot: it only fires on a `served` order that is
--        fully settled, and the very first thing it does is re-read the status under
--        the held lock. An order that is already `completed` (a retry, a replay, or
--        the loser of a race) is left alone and reports completed=false, so no second
--        transition and no duplicate audit event can ever occur.
-- ---------------------------------------------------------------------------
create or replace function app.try_auto_complete_order(
  p_organization_id           uuid,
  p_restaurant_id             uuid,
  p_branch_id                 uuid,
  p_order_id                  uuid,
  p_trigger                   text,   -- 'order_served' | 'payment_recorded'
  p_actor_app_user_id         uuid,   -- the REAL initiating actor (JWT path)
  p_actor_employee_profile_id uuid,   -- the REAL initiating actor (PIN path)
  p_actor_membership_id       uuid,
  p_actor_role                text,
  p_device_id                 uuid,
  p_local_operation_id        text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_status     text;
  v_rev        integer;
  v_new_rev    integer;
  v_total      bigint;  -- the order's CURRENT total: decides chargeable vs not
  v_err_state  text;    -- fail-soft diagnostics (see the exception handler)
  v_err_msg    text;
  v_order_code text := '#' || upper(right(replace(p_order_id::text, '-', ''), 6));
begin
  -- The order row is ALREADY locked by the caller; this re-read is a no-op
  -- re-acquire in the same transaction and gives us the CURRENT committed state.
  select o.status, o.revision, o.grand_total_minor
    into v_status, v_rev, v_total
    from public.orders o
    where o.id              = p_order_id
      and o.organization_id = p_organization_id
      and o.deleted_at is null
    for update;

  -- Not our case: not served (submitted/accepted/preparing/ready stay put), already
  -- terminal (completed/cancelled/voided are NEVER revived), or gone.
  if not found or v_status <> 'served' then
    return jsonb_build_object('completed', false, 'reason', 'not_eligible');
  end if;

  -- The authoritative SETTLEMENT test. An unpaid served order stays served and
  -- stays visible in Awaiting close — that is the point.
  if not app.order_is_fully_settled(p_organization_id, p_order_id) then
    return jsonb_build_object('completed', false, 'reason', 'not_fully_paid');
  end if;

  -- The ONLY mutation: status + revision. No payment is created or touched, no
  -- total is recomputed, no table/shift/receipt is affected.
  v_new_rev := v_rev + 1;
  update public.orders
    set status = 'completed', revision = v_new_rev
    where id = p_order_id;

  -- ONE canonical audit event, naming the REAL initiating actor and device, and
  -- proving this was automatic and why. Money-free (T-003).
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    p_organization_id, p_restaurant_id, p_branch_id,
    p_actor_app_user_id, p_actor_employee_profile_id, p_device_id,
    'order.status_updated', null,
    jsonb_build_object('order_id', p_order_id, 'status', 'served', 'revision', v_rev),
    jsonb_build_object(
      'order_id',              p_order_id,
      'order_code',            v_order_code,
      'status',                'completed',
      'revision',              v_new_rev,
      'resolved_membership_id', p_actor_membership_id,
      'role',                  p_actor_role,
      'local_operation_id',    p_local_operation_id,
      -- THE AUDIT MUST NOT LIE (D-013, invariant 8 — this trail is append-only and
      -- can never be corrected). A ZERO-TOTAL order settles with NO payment row, so
      -- writing 'paid' here would assert a payment that was never taken — and the
      -- owner would see the SAME order as `unpaid` in the Orders list, which derives
      -- its payment_status from the existence of a payments row. Say what is true:
      -- there was nothing to pay.
      'payment_status',        case when v_total = 0 then 'not_chargeable' else 'paid' end,
      'completion_mode',       'automatic',
      'completion_trigger',    p_trigger));

  return jsonb_build_object(
    'completed', true, 'revision', v_new_rev, 'trigger', p_trigger,
    'order_code', v_order_code);
exception
  -- FAIL SOFT, ALWAYS — BUT NEVER SILENTLY.
  --
  --  * FAIL SOFT: a successful payment (or a successful `served` transition) must
  --    never be turned into a client-visible failure by its own SIDE EFFECT. The POS
  --    payment parser is fail-closed and treats any non-`applied` result as a FAILED
  --    payment, so re-raising here would tell a cashier the money was not taken when
  --    it was. We therefore swallow the error instead of propagating it.
  --  * NEVER SILENTLY: an unexpected error here is a real defect, so it is RAISEd as
  --    a WARNING carrying the SQLSTATE and the message. That reaches the PostgreSQL
  --    server log at the default log_min_messages, giving an operator something
  --    diagnosable to find; a WARNING cannot abort the transaction, so the payment
  --    still commits. The SQLSTATE (never the message) is also returned to the caller
  --    in `error_code`.
  --  * NOTHING PARTIAL, NO FAKE SUCCESS: the `update orders` and the audit `insert`
  --    above both run inside THIS block's implicit savepoint, so if either one fails
  --    BOTH are rolled back. The order stays `served`, NO audit row exists, and we
  --    report completed=false. There is no path that can write a SUCCESS audit event
  --    for a completion that did not actually happen.
  when others then
    get stacked diagnostics
      v_err_state = returned_sqlstate,
      v_err_msg   = message_text;
    raise warning
      'ORDER-AUTO-COMPLETION-001 app.try_auto_complete_order FAILED (fail-soft): order_id=% trigger=% sqlstate=% message=%',
      p_order_id, p_trigger, v_err_state, v_err_msg;
    return jsonb_build_object(
      'completed',  false,
      'reason',     'auto_completion_failed',
      'error_code', v_err_state);
end;
$$;

comment on function app.try_auto_complete_order(uuid, uuid, uuid, uuid, text, uuid, uuid, uuid, text, uuid, text) is
  'ORDER-AUTO-COMPLETION-001: the ONE automatic served -> completed decision, shared by both trigger directions (chained at the tail of app.apply_order_status_transition when a transition lands on `served`, and at the tail of app.record_payment when an order becomes fully paid). PRECONDITION: the caller already holds the order row lock (both do), so this adds NO lock and cannot deadlock. It fires ONLY on a `served` order that app.order_is_fully_settled reports as settled (integer minor units); an unpaid served order is left active. It does NOT re-run the role gate — authorization already passed on the triggering operation, and the automatic step is a system-rule consequence, not a second human decision (the manual fronts keep the frozen role gate untouched). IDEMPOTENT: it re-reads the status under the held lock, so an already-completed order (retry, replay, or the loser of a race) is left alone -> no duplicate transition, no duplicate audit event. It NEVER RAISES (fail-soft), because a failure here must never turn a successful payment into a failed one. Writes orders.status + revision and ONE money-free order.status_updated audit carrying completion_mode=automatic + completion_trigger + the safe order_code. INTERNAL: granted to no client role.';


-- ---------------------------------------------------------------------------
-- 3. app.apply_order_status_transition — the SHARED state-machine core, faithfully
--    re-created from ORDER-COMPLETION-001 with exactly THREE surgical changes:
--      (i)   the D-025 gate now uses app.order_is_fully_settled (a SETTLEMENT test
--            instead of a marker test) — this hardens the MANUAL path too;
--      (ii)  TRIGGER DIRECTION A: when a transition lands on `served`, the automatic
--            completion is chained under the SAME order row lock already held;
--      (iii) the envelope reports `auto_completed` and the FINAL status.
--    The legality CASE, the role gate, the locking and the audit shape are UNCHANGED.
--    No new transition edge is added: direction A chains a SECOND, already-legal
--    single-step transition (served -> completed); it does not widen the table.
-- ---------------------------------------------------------------------------
create or replace function app.apply_order_status_transition(
  p_order_id                  uuid,
  p_new_status                text,
  p_actor_org                 uuid,
  p_actor_restaurant          uuid,
  p_actor_branch              uuid,
  p_actor_role                text,
  p_actor_app_user_id         uuid,      -- JWT actor  (null on the device path)
  p_actor_employee_profile_id uuid,      -- PIN actor  (null on the JWT path)
  p_actor_membership_id       uuid,
  p_device_id                 uuid,      -- null on the JWT path
  p_local_operation_id        text,      -- null on the JWT path
  p_expected_revision         integer default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_o_org      uuid;
  v_o_branch   uuid;
  v_o_status   text;
  v_o_rev      integer;
  v_legal      boolean;
  v_new_rev    integer;
  v_paid       boolean;
  v_o_total    bigint;   -- the order's CURRENT total: chargeable vs not_chargeable
  v_auto       jsonb;
  v_order_code text := '#' || upper(right(replace(p_order_id::text, '-', ''), 6));
begin
  -- (a) load the order FOR UPDATE (serializes concurrent status pushes); it MUST
  --     be in the actor's organization AND branch. Cross-tenant -> fail-closed
  --     raise, no write.
  select o.organization_id, o.branch_id, o.status, o.revision, o.grand_total_minor
    into v_o_org, v_o_branch, v_o_status, v_o_rev, v_o_total
    from public.orders o where o.id = p_order_id
    for update;
  if not found then
    raise exception 'update_order_status: order not found' using errcode = '42501';
  end if;
  if v_o_org <> p_actor_org or v_o_branch <> p_actor_branch then
    raise exception 'update_order_status: order is not in the caller scope' using errcode = '42501';
  end if;

  -- (b) OPTIMISTIC CONCURRENCY (opt-in; the PIN front passes null, preserving its
  --     exact behaviour). A stale client that read revision N cannot overwrite a
  --     newer state: it gets the documented `revision_mismatch` with the server's
  --     revision so it can re-read. (API_CONTRACT §2 error model.)
  if p_expected_revision is not null and p_expected_revision <> v_o_rev then
    return jsonb_build_object('ok', false, 'error', 'revision_mismatch',
                              'order_id', p_order_id, 'status', v_o_status,
                              'server_revision', v_o_rev,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (c) transition legality: SINGLE-STEP forward only over the FROZEN states
  --     (D-018, STATE_MACHINES §1.1). Skips, backwards, terminal sources
  --     (completed/cancelled/voided), unknown targets, and from==to are all
  --     invalid_transition (returned, not raised — a permanent per-op rejection
  --     through sync_push; no state change). The client can NEVER choose an
  --     arbitrary next status: only these five (from, to) pairs exist.
  v_legal := case
    when v_o_status = 'submitted' and p_new_status = 'accepted'  then true
    when v_o_status = 'accepted'  and p_new_status = 'preparing' then true
    when v_o_status = 'preparing' and p_new_status = 'ready'     then true
    when v_o_status = 'ready'     and p_new_status = 'served'    then true
    when v_o_status = 'served'    and p_new_status = 'completed' then true
    else false end;
  if not v_legal then
    return jsonb_build_object('ok', false, 'error', 'invalid_transition',
                              'from', v_o_status, 'to', p_new_status, 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) role authorization: the production + service steps (->accepted/->preparing/
  --     ->ready/->served — the last is the KDS "bump") allow kitchen_staff + cashier
  --     + manager + restaurant_owner + org_owner; the settlement step (->completed)
  --     EXCLUDES kitchen_staff. A denial is audited (order.status_update_denied —
  --     NO money fields) and RETURNED (no raise, so the audit persists), with NO
  --     state change.
  if p_actor_role not in ('kitchen_staff', 'cashier', 'manager', 'restaurant_owner', 'org_owner')
     or (p_actor_role = 'kitchen_staff' and p_new_status = 'completed') then
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
    values (p_actor_org, p_actor_restaurant, p_actor_branch, p_actor_app_user_id, p_actor_employee_profile_id, p_device_id,
            'order.status_update_denied', null, null,
            jsonb_build_object('attempted_action', 'update_order_status', 'order_id', p_order_id,
                               'order_code', v_order_code,
                               'role', p_actor_role, 'from', v_o_status, 'to', p_new_status,
                               'local_operation_id', p_local_operation_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied',
                              'order_id', p_order_id, 'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (e) D-025 PAYMENT GATE (ORDER-COMPLETION-001) — an order reaches `completed`
  --     only when payment is `completed`. Derived, never fabricated: "paid" is the
  --     existence of a completed, live payments row (the SAME derivation the
  --     reports and owner_active_orders use). This creates NO payment and changes
  --     NO payments row. A business rejection, NOT an authorization denial, so —
  --     like invalid_transition — it is RETURNED and deliberately NOT audited (the
  --     denied-attempt audit is reserved for authorization failures).
  if p_new_status = 'completed' then
    -- ORDER-AUTO-COMPLETION-001: the ONE authoritative settlement test (integer
    -- minor units). Replaces the bare exists()-a-completed-payment MARKER test:
    -- app.apply_discount can re-base grand_total_minor after a payment is taken, so
    -- a marker could report a partially-settled order as paid. Identical to the old
    -- test in every normal case (the stored amount IS the order total).
    v_paid := app.order_is_fully_settled(v_o_org, p_order_id);
    if not v_paid then
      return jsonb_build_object('ok', false, 'error', 'order_not_paid',
                                'order_id', p_order_id, 'from', v_o_status, 'to', p_new_status,
                                'server_ts', now(), 'idempotency_replay', false);
    end if;
  end if;

  -- (f) mutate: status forward one step; bump revision (updated_at bumps via the
  --     RF-052 set_updated_at trigger, feeding the sync_pull change cursor).
  --     orders.status + orders.revision are the ONLY columns written. No payment,
  --     no shift, no table, no receipt, no total is touched.
  v_new_rev := v_o_rev + 1;
  update public.orders
    set status = p_new_status, revision = v_new_rev
    where id = p_order_id;

  -- (g) audit order.status_updated (D-013) — old/new STATUS + revision + actor
  --     linkage + the SAFE order_code, plus the derived payment_status on a
  --     completion. Deliberately NO money fields: a kitchen actor drives the
  --     production steps of this path and must never put a money figure on the
  --     wire or in its audit (T-003).
  insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
  values (p_actor_org, p_actor_restaurant, p_actor_branch, p_actor_app_user_id, p_actor_employee_profile_id, p_device_id,
          'order.status_updated', null,
          jsonb_build_object('order_id', p_order_id, 'status', v_o_status, 'revision', v_o_rev),
          jsonb_build_object('order_id', p_order_id, 'order_code', v_order_code,
                             'status', p_new_status, 'revision', v_new_rev,
                             'resolved_membership_id', p_actor_membership_id, 'role', p_actor_role,
                             'local_operation_id', p_local_operation_id)
          -- THE AUDIT MUST NOT LIE (D-013): a ZERO-TOTAL order is completed WITHOUT a
          -- payment row, so 'paid' would assert a payment that was never taken. State
          -- the truth — there was nothing to pay.
          || case when p_new_status = 'completed'
                  then jsonb_build_object('payment_status',
                                          case when v_o_total = 0 then 'not_chargeable'
                                               else 'paid' end,
                                          'completion_mode', 'manual')
                  else '{}'::jsonb end);

  -- (h) TRIGGER DIRECTION A (ORDER-AUTO-COMPLETION-001): the order just reached
  --     `served`. If it is ALREADY fully paid, complete it now — in this same
  --     transaction, under the order row lock we already hold. The `served`
  --     transition above stands on its own and is NEVER failed by this: an unpaid
  --     order simply stays served (and stays visible in Awaiting close). The helper
  --     never raises, and it does not re-run the role gate — the kitchen actor was
  --     already authorized to make THIS transition, and the completion is a
  --     system-rule consequence of it, not a second human decision.
  if p_new_status = 'served' then
    v_auto := app.try_auto_complete_order(
      p_actor_org, p_actor_restaurant, p_actor_branch, p_order_id,
      'order_served',
      p_actor_app_user_id, p_actor_employee_profile_id, p_actor_membership_id,
      p_actor_role, p_device_id, p_local_operation_id);
    if (v_auto ->> 'completed')::boolean then
      -- Report the FINAL state, so the caller (and the sync ledger) never records a
      -- status the order is no longer in.
      return jsonb_build_object('ok', true, 'entity', 'order', 'order_id', p_order_id,
                                'order_code', v_order_code,
                                'status', 'completed',
                                'revision', (v_auto ->> 'revision')::integer,
                                'auto_completed', true,
                                'completion_trigger', 'order_served',
                                'server_ts', now(), 'idempotency_replay', false);
    end if;
  end if;

  return jsonb_build_object('ok', true, 'entity', 'order', 'order_id', p_order_id,
                            'order_code', v_order_code,
                            'status', p_new_status, 'revision', v_new_rev,
                            'auto_completed', false,
                            'server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.apply_order_status_transition(uuid, text, uuid, uuid, uuid, text, uuid, uuid, uuid, uuid, text, integer) is
  'ORDER-COMPLETION-001 + ORDER-AUTO-COMPLETION-001: the ACTOR-AGNOSTIC CORE of the order state machine (D-018, STATE_MACHINES §1.1) — the SINGLE implementation of scope re-check, single-step transition legality, role authorization, the D-025 payment gate, the write and the audit. The D-025 gate is now app.order_is_fully_settled (integer minor units: a live completed payment whose amount covers the CURRENT grand_total_minor) — a SETTLEMENT test, not a marker test. AUTO-COMPLETION (direction A): when a transition lands on `served` and the order is already fully paid, app.try_auto_complete_order completes it in the SAME transaction under the SAME order row lock, and the envelope reports auto_completed + the FINAL status; an unpaid order simply stays served. It resolves NO actor and trusts NO client: the caller (app.update_order_status for a PIN/device principal, app.owner_complete_order for a JWT principal) must already have authenticated the actor and established scope coverage. INTERNAL: not granted to any client role.';


-- ---------------------------------------------------------------------------
-- 4. app.record_payment — faithfully re-created from RF-117 (the newest of its four
--    stacked definitions) with exactly TWO surgical changes:
--      (i)  TRIGGER DIRECTION B: after the payment is written, an already-`served`
--           order is completed under the SAME order row lock this function has held
--           since step (b);
--      (ii) the envelope reports `auto_completed` + the resulting `order_status`.
--    The auth gates, the shift/drawer preconditions, the settlement math, the
--    at-most-one-completed-payment guard, the receipt numbering, the payment insert
--    and BOTH existing audits are UNCHANGED — a payment still records exactly what it
--    recorded before, and this function still creates no order-status side effect of
--    its own beyond the automatic completion rule.
-- ---------------------------------------------------------------------------
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
  v_auto          jsonb;   -- ORDER-AUTO-COMPLETION-001 (trigger direction B)
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

  -- (n) TRIGGER DIRECTION B (ORDER-AUTO-COMPLETION-001): the order has just become
  --     FULLY PAID. If it is ALREADY `served`, complete it now — in this same
  --     transaction, under the order row lock this function has held since step (b),
  --     so there is NO new lock and NO new lock order. An order in
  --     submitted/accepted/preparing/ready is left exactly where it is; a terminal
  --     order is never revived. The helper NEVER RAISES: a failure here must never
  --     turn this SUCCESSFUL payment into a client-visible failure (the POS payment
  --     parser is fail-closed and treats any non-`applied` result as a failed
  --     payment). Payment state is NOT changed by this — the payment row is already
  --     written and is never touched again.
  v_auto := app.try_auto_complete_order(
    v_org, v_rest, v_branch, p_order_id,
    'payment_recorded',
    null, v_emp, v_membership, v_role, p_device_id, p_local_operation_id);
  if (v_auto ->> 'completed')::boolean then
    v_new_rev := (v_auto ->> 'revision')::integer;   -- report the FINAL revision
  end if;

  -- (o) record the idempotency ledger result + return
  v_result := jsonb_build_object(
    'ok', true, 'payment_id', v_payment_id, 'order_id', p_order_id,
    'method', p_tender_type, 'receipt_number', v_receipt_no, 'change_due_minor', v_change,
    'shift_id', v_shift_id, 'cash_drawer_session_id', v_drawer_id,
    'payment_revision', 1, 'order_revision', v_new_rev,
    -- Additive keys; existing clients ignore what they do not read.
    'auto_completed', coalesce((v_auto ->> 'completed')::boolean, false),
    'order_status', case when coalesce((v_auto ->> 'completed')::boolean, false)
                         then 'completed' else v_o_status end);
  insert into public.order_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, order_id, result)
    values (v_org, v_rest, v_branch, p_device_id, p_local_operation_id, 'record_payment', p_order_id, v_result);
  return v_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.record_payment(uuid, uuid, uuid, text, text, bigint, text, integer) is
  'RF-054/RF-055/RF-117 + ORDER-AUTO-COMPLETION-001 (API_CONTRACT §4.7, D-011) SECURITY DEFINER RPC: records a payment + assigns the per-branch receipt number (D-021). Tender cash|card|bit|external; CASH keeps tendered>=grand_total + change=tendered-grand_total; NON-CASH records amount=tendered=grand_total, change=0. Requires an open shift + active bound cash drawer and stamps shift_id/cash_drawer_session_id. PIN-session auth; cashier+ only; order-bound idempotency; at most one completed payment per order. AUTO-COMPLETION (direction B): after the payment is written, if the order is ALREADY `served` and is now fully settled, app.try_auto_complete_order completes it in the SAME transaction under the order row lock this function already holds (no new lock, no new lock order); an order in submitted/accepted/preparing/ready is left untouched, and a terminal order is never revived. The helper NEVER RAISES, so a successful payment can never be surfaced as a failed one. The payment row itself is NEVER modified. It still does NOT advance orders.status by itself (D-025) — the automatic rule does, and only for served+fully-paid. Writes payment.recorded + receipt_number.assigned (D-013), plus ONE order.status_updated (completion_mode=automatic) when it auto-completes.';


-- ---------------------------------------------------------------------------
-- 5. app.audit_safe_detail — faithfully re-created (the ORDER-COMPLETION-001 body,
--    which already carries order_code/payment_status) with TWO keys appended to the
--    scalar allowlist. Without this the new fields would be silently DROPPED: the
--    projection is an allowlist, not a denylist.
--    app.audit_category and app.audit_action_has_detail need NO change —
--    'order.status_updated' already classifies as ORDERS and already carries detail.
-- ---------------------------------------------------------------------------
create or replace function app.audit_safe_detail(p_action text, p_values jsonb)
  returns jsonb
  language plpgsql
  immutable
  set search_path = ''
as $$
declare
  v_out  jsonb := '{}'::jsonb;
  v_caps jsonb;
  v_key  text;
begin
  -- Unknown / unsupported action -> no payload details.
  if not app.audit_action_has_detail(p_action) then
    return '{}'::jsonb;
  end if;
  -- Malformed / missing / non-object payload -> empty safe detail (never throws).
  if p_values is null or jsonb_typeof(p_values) <> 'object' then
    return '{}'::jsonb;
  end if;

  -- Canonical SAFE SCALAR allowlist. A key is emitted ONLY when it is on this
  -- list AND its value is a scalar (string/number/boolean) — nested objects,
  -- arrays, and every un-listed key (secret OR merely unknown) are dropped.
  foreach v_key in array array[
    'status','order_status','scope','discount_type','value','attempted_action','order_type',
    'role','from_role','to_role','target_role',
    'discount_total_minor','grand_total_minor','subtotal_minor','line_total_minor','line_discount_minor',
    'amount_minor','tendered_minor','change_minor','opening_float_minor',
    'expected_cash_minor','counted_cash_minor','cash_variance_minor','variance_minor',
    'voided_item_count','failed_attempt_count','locked',
    'timezone','name','receipt_prefix',
    'order_code','payment_status',
    -- ORDER-AUTO-COMPLETION-001: how, and why, an order was completed. Both are
    -- STATES ('automatic'/'manual', 'order_served'/'payment_recorded'), not money
    -- and not identifiers — T-003 still holds.
    'completion_mode','completion_trigger'
  ] loop
    if p_values ? v_key
       and jsonb_typeof(p_values -> v_key) in ('string','number','boolean') then
      v_out := v_out || jsonb_build_object(v_key, p_values -> v_key);
    end if;
  end loop;

  -- The ONLY allowlisted nested object: `capabilities`, kept to its three
  -- canonical boolean capability keys (unknown nested keys dropped).
  if jsonb_typeof(p_values -> 'capabilities') = 'object' then
    select coalesce(jsonb_object_agg(k, p_values -> 'capabilities' -> k), '{}'::jsonb)
      into v_caps
      from unnest(array['apply_discount','void_order','close_shift']) as k
      where (p_values -> 'capabilities') ? k
        and jsonb_typeof(p_values -> 'capabilities' -> k) in ('string','number','boolean');
    if v_caps is distinct from '{}'::jsonb then
      v_out := v_out || jsonb_build_object('capabilities', v_caps);
    end if;
  end if;

  return v_out;
end;
$$;

comment on function app.audit_safe_detail(text, jsonb) is
  'AUDIT-LOG-DASHBOARD-001 + AUDIT-COVERAGE-002 + ORDER-COMPLETION-001 + ORDER-AUTO-COMPLETION-001: ALLOWLIST projection of ONE audit payload (old or new) to canonical safe fields. Gated by app.audit_action_has_detail (unsupported action -> ''{}''). Emits only allowlisted scalar keys (status/scope/discount_type/value/attempted_action/order_type/roles/*_minor money/voided_item_count/failed_attempt_count/locked/timezone/name/receipt_prefix/order_code/payment_status + completion_mode/completion_trigger) plus the nested `capabilities` object. completion_mode (automatic|manual) and completion_trigger (order_served|payment_recorded) are STATES, not money and not identifiers (T-003 holds). Every un-listed key (secret OR unknown) and every other nested structure is DROPPED. Malformed/non-object -> ''{}''; never throws. This is the server-side privacy boundary; the RPC returns NO raw payload JSON.';

-- ---------------------------------------------------------------------------
-- 6. Grants. Both new helpers are INTERNAL: no client role may execute them. The
--    SECURITY DEFINER callers run as the function owner and reach them that way.
--    `anon` is revoked EXPLICITLY (a revoke-from-PUBLIC does NOT remove the grant
--    hosted Supabase's ALTER DEFAULT PRIVILEGES hands to anon at CREATE time).
-- ---------------------------------------------------------------------------
revoke all on function app.order_is_fully_settled(uuid, uuid) from public;
revoke all on function app.order_is_fully_settled(uuid, uuid) from anon;
revoke all on function app.order_is_fully_settled(uuid, uuid) from authenticated;

revoke all on function app.try_auto_complete_order(uuid, uuid, uuid, uuid, text, uuid, uuid, uuid, text, uuid, text) from public;
revoke all on function app.try_auto_complete_order(uuid, uuid, uuid, uuid, text, uuid, uuid, uuid, text, uuid, text) from anon;
revoke all on function app.try_auto_complete_order(uuid, uuid, uuid, uuid, text, uuid, uuid, uuid, text, uuid, text) from authenticated;

-- The re-created functions keep EXACTLY the ACL they already had.
revoke all on function app.apply_order_status_transition(uuid, text, uuid, uuid, uuid, text, uuid, uuid, uuid, uuid, text, integer) from public;
revoke all on function app.apply_order_status_transition(uuid, text, uuid, uuid, uuid, text, uuid, uuid, uuid, uuid, text, integer) from anon;
revoke all on function app.apply_order_status_transition(uuid, text, uuid, uuid, uuid, text, uuid, uuid, uuid, uuid, text, integer) from authenticated;

revoke all on function app.record_payment(uuid, uuid, uuid, text, text, bigint, text, integer) from public;
revoke all on function app.record_payment(uuid, uuid, uuid, text, text, bigint, text, integer) from anon;
grant execute on function app.record_payment(uuid, uuid, uuid, text, text, bigint, text, integer) to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   -- restore app.apply_order_status_transition + app.audit_safe_detail from
--   -- 20260713090000, and app.record_payment from 20260704150000, then:
--   drop function if exists app.try_auto_complete_order(uuid, uuid, uuid, uuid, text, uuid, uuid, uuid, text, uuid, text);
--   drop function if exists app.order_is_fully_settled(uuid, uuid);
-- ROLLBACK NOTE: restoring those three bodies stops all future auto-completion
-- immediately. Orders already auto-completed STAY completed — `completed` is
-- terminal (D-024) and this migration rewrites no history. They remain correct:
-- each was served AND fully settled, and each carries its own audit event.
-- ============================================================================
