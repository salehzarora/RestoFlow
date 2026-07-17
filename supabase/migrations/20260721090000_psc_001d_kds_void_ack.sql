-- ============================================================================
-- PSC-001D — KDS cancellation acknowledgement
-- ============================================================================
-- When a cashier voids an unpaid order the kitchen may already be preparing,
-- the order silently vanished from the KDS board. This migration makes the
-- cancellation SERVER-AUTHORITATIVELY visible until the kitchen explicitly
-- acknowledges it:
--
--   * orders gains VOID PROVENANCE (voided_at, voided_from_status) and the
--     KITCHEN ACKNOWLEDGEMENT state (kitchen_ack_required + the write-once
--     ack triple: at / employee / device). Voids from an ACTIVE kitchen state
--     (submitted|accepted|preparing|ready) require one branch-wide
--     acknowledgement; a void from `served` does not (already off the board).
--     Historical rows are untouched and valid (all-NULL / default false — no
--     backfill, no retroactive acknowledgement demands).
--   * app.void_order is re-created FAITHFULLY (20260716090000 body) with ONE
--     semantic addition: the success mutate stamps the provenance columns.
--     Eligibility, the paid-order guard, every denial, audit, idempotency and
--     ACL are byte-preserved.
--   * NEW app.kitchen_ack_void — the acknowledgement RPC. KDS-CLASS DEVICES
--     ONLY (devices.device_type = 'kds'; a POS device is refused regardless of
--     role, so the voiding cashier cannot defeat the safeguard) with roles
--     kitchen_staff|manager|restaurant_owner|org_owner. Expected refusals are
--     RETURN-typed after a safe order.void_ack_denied audit; scope probes keep
--     the anti-oracle structural 42501. Idempotent: an already-acknowledged
--     order replays success (already_acknowledged=true) with no second write
--     and no second audit.
--   * app.sync_push is re-created FAITHFULLY (20260720110000 body) adding ONLY
--     operation #13 `order.void_ack` (CHECK + both allowlists + dispatch arm
--     with a target_id/payload consistency guard). All 12 prior operations,
--     the ledger, dependencies, batch cap and error envelopes are preserved.
--   * app.audit_safe_detail is re-created FAITHFULLY adding ONLY the safe
--     scalar keys voided_from_status / device_type / kitchen_ack_required.
--     app.audit_category and app.audit_action_has_detail are NOT touched:
--     the existing `order.void%` family already classifies both new actions
--     into `voids` and detail-enables them.
--
-- The KDS read path is UNCHANGED: app.sync_pull's generic pager has no status
-- filter and returns to_jsonb(row), so voided orders/items and the new
-- non-money columns already flow to the kitchen (app.redact_money strips only
-- `minor`-token + receipt keys); the acknowledgement bumps orders.revision so
-- the RF-052 updated_at trigger re-delivers the row to every device's cursor.
--
-- FORWARD-ONLY (Supabase replays on db reset). Teardown at the foot.
-- NOT applied to hosted by this migration. PENDING: RISK R-003 sign-off.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. orders — void provenance + kitchen acknowledgement state (additive; every
--    pre-existing row stays valid: NULLs / default false throughout).
-- ----------------------------------------------------------------------------
alter table public.orders
  add column voided_at            timestamptz,
  add column voided_from_status   text,
  add column kitchen_ack_required boolean not null default false,
  add column kitchen_ack_at       timestamptz,
  add column kitchen_ack_by_employee_profile_id uuid,
  add column kitchen_ack_device_id uuid;

comment on column public.orders.voided_at is
  'PSC-001D: when app.void_order voided this order (write-once, server clock). NULL on every non-voided order and on historical voids that predate the phase.';
comment on column public.orders.voided_from_status is
  'PSC-001D: the order status at the moment of the void (submitted|accepted|preparing|ready|served), write-once. Drives kitchen_ack_required and the KDS red-card column placement.';
comment on column public.orders.kitchen_ack_required is
  'PSC-001D: TRUE when the void happened while the order was in an ACTIVE kitchen state (submitted|accepted|preparing|ready) and the kitchen must explicitly acknowledge the cancellation. FALSE for served-source voids and for every historical row.';
comment on column public.orders.kitchen_ack_at is
  'PSC-001D: when a KDS-class actor acknowledged the cancellation (write-once; branch-wide). NULL while the red card must stay on the kitchen board.';
comment on column public.orders.kitchen_ack_by_employee_profile_id is
  'PSC-001D: the PIN actor (employee profile) who acknowledged, same-org proven by FK. Set together with kitchen_ack_at.';
comment on column public.orders.kitchen_ack_device_id is
  'PSC-001D: the KDS device the acknowledgement came from — the 4-part composite FK proves it belongs to the order''s EXACT org/restaurant/branch (D-012 layer 4). Set together with kitchen_ack_at.';

-- Provenance is a closed enum or absent.
alter table public.orders add constraint orders_voided_from_status_check
  check (voided_from_status is null
         or voided_from_status in ('submitted','accepted','preparing','ready','served'));

-- Provenance fields travel TOGETHER, and only on a voided order. Historical
-- voided rows (both NULL) remain valid; `voided` is terminal, so no status
-- transition can ever strand a stamped row.
alter table public.orders add constraint orders_void_provenance_check
  check ((voided_at is null and voided_from_status is null)
         or (voided_at is not null and voided_from_status is not null
             and status = 'voided'));

-- An acknowledgement demand only ever exists on a provenance-stamped void.
alter table public.orders add constraint orders_kitchen_ack_required_check
  check (not kitchen_ack_required
         or (status = 'voided'
             and voided_at is not null
             and voided_from_status is not null));

-- The acknowledgement triple is all-or-none, and only on a void that REQUIRED
-- acknowledgement (which itself implies status='voided').
alter table public.orders add constraint orders_kitchen_ack_state_check
  check (((kitchen_ack_at is null) = (kitchen_ack_by_employee_profile_id is null))
         and ((kitchen_ack_at is null) = (kitchen_ack_device_id is null))
         and (kitchen_ack_at is null or kitchen_ack_required));

-- Same-org / same-branch structural proof (D-012 layer 4), matching the
-- conventions the orders table already uses (RF-052): employee = same-org
-- composite; device = the 4-part composite that pins the acknowledging device
-- to the order's exact branch.
alter table public.orders add constraint orders_kitchen_ack_employee_fkey
  foreign key (organization_id, kitchen_ack_by_employee_profile_id)
  references public.employee_profiles (organization_id, id) on delete restrict;
alter table public.orders add constraint orders_kitchen_ack_device_fkey
  foreign key (organization_id, restaurant_id, branch_id, kitchen_ack_device_id)
  references public.devices (organization_id, restaurant_id, branch_id, id) on delete restrict;

-- No new index: no server query filters on these columns (the KDS filter is
-- client-side over the already-branch-scoped pull, and pending acknowledgements
-- are a handful of rows per branch).

-- ----------------------------------------------------------------------------
-- 2. app.void_order — CREATE OR REPLACE (keeps ACLs). FAITHFUL re-creation of
--    the MONEY-SETTLEMENT-CONSISTENCY-001 body (20260716090000) with exactly
--    ONE semantic addition at step (h): the success mutate stamps voided_at,
--    voided_from_status and kitchen_ack_required, and the success audit's
--    new_values carries the two safe provenance scalars. Eligibility, the
--    completed-payment guard, every refusal shape, the item cascade, the
--    idempotency ledger and the audits are otherwise byte-unchanged.
-- ----------------------------------------------------------------------------
create or replace function app.void_order(
  p_pin_session_id     uuid,
  p_order_id           uuid,
  p_device_id          uuid,
  p_local_operation_id text,
  p_reason             text,
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
  v_m_perms      jsonb;
  v_o_org        uuid;
  v_o_branch     uuid;
  v_o_status     text;
  v_o_rev        integer;
  v_authorized   boolean;
  v_new_rev      integer;
  v_voided_items integer;
  v_stored       jsonb;
  v_stored_order uuid;
  v_result       jsonb;
begin
  -- (a) PIN session + backing device session/pairing; derive actor + scope
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'void_order: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'void_order: PIN session is not valid' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'void_order: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'void_order: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at, m.permissions
    into v_role, v_m_status, v_m_deleted, v_m_perms
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'void_order: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) load the order; it MUST be in the actor's org + branch (no cross-tenant).
  --     RF-062 (A4): FOR UPDATE locks the order row so void_order serializes with
  --     record_payment (which now also locks the order row) on the SAME order — a
  --     payment cannot complete between the (g2) guard and the void.
  select o.organization_id, o.branch_id, o.status, o.revision
    into v_o_org, v_o_branch, v_o_status, v_o_rev
    from public.orders o where o.id = p_order_id
    for update;
  if not found then
    raise exception 'void_order: order not found' using errcode = '42501';
  end if;
  if v_o_org <> v_org or v_o_branch <> v_branch then
    raise exception 'void_order: order is not in the caller scope' using errcode = '42501';
  end if;

  -- (c) authorization (A1): manager/restaurant_owner/org_owner, OR a cashier with an
  --     explicit memberships.permissions->>'void_order' = 'true' grant. RF053-B1:
  --     authorization runs BEFORE the idempotency replay so an unauthorized actor can
  --     never replay a prior SUCCESS result. A DENIAL is audited (order.void_denied)
  --     + RETURNED (no raise, so the audit persists) with NO state change and NO ledger
  --     write (the ledger holds only authorized successes; denials are always re-audited
  --     as probe attempts, never replayed).
  v_authorized := (v_role in ('manager', 'restaurant_owner', 'org_owner'))
                  or app.cashier_capability_allowed(v_role, v_m_perms, 'void_order');

  if not v_authorized then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.void_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
      jsonb_build_object('attempted_action', 'void_order', 'order_id', p_order_id,
                         'role', v_role, 'order_status', v_o_status));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) reason mandatory (AC#2)
  if btrim(coalesce(p_reason, '')) = '' then
    raise exception 'void_order: a non-empty reason is required' using errcode = '42501';
  end if;

  -- (e) idempotency replay (RF053-B1): AFTER authorization + reason, BEFORE the
  --     voidable-source-state check (the order becomes 'voided' after the first
  --     success). ORDER-BOUND: the stored op MUST be for the same order; the same
  --     (org, device, local_operation_id, action) reused on a DIFFERENT order is a
  --     conflict, not a replay (never leaks the original order's result).
  select oo.result, oo.order_id into v_stored, v_stored_order
    from public.order_operations oo
    where oo.organization_id = v_org and oo.device_id = p_device_id
      and oo.local_operation_id = p_local_operation_id and oo.action = 'void_order';
  if found then
    if v_stored_order <> p_order_id then
      raise exception 'void_order: idempotency key already used for a different order (%, not %)', v_stored_order, p_order_id using errcode = '40001';
    end if;
    return v_stored || jsonb_build_object('server_ts', now(), 'idempotency_replay', true);
  end if;

  -- (f) optimistic concurrency (optional)
  if p_expected_revision is not null and p_expected_revision <> v_o_rev then
    raise exception 'void_order: revision conflict (expected %, got %)', p_expected_revision, v_o_rev using errcode = '40001';
  end if;

  -- (g) state legality (AC#3, D-024): only pre-completion non-terminal source states.
  --     ELIGIBILITY IS UNCHANGED — the legal set is still exactly
  --     submitted/accepted/preparing/ready/served, `completed` remains TERMINAL, and there
  --     is NO completed -> void path. Only the SHAPE of the refusal changes.
  --
  --     MONEY-SETTLEMENT-CONSISTENCY-001 (corrective): RETURN the stable domain code
  --     instead of raising. app.sync_push REBUILDS the envelope from scratch for a RAISE
  --     (collapsing every domain code to the generic literal 'rejected'), but merges a
  --     RETURNED envelope through VERBATIM. Raising left the POS unable to tell
  --     "this order is already closed" apart from a dropped network, a malformed response
  --     or any other rejection — so it was reduced to GUESSING from the order's total, and
  --     could tell an operator an order was closed when the connection had merely failed.
  --
  --     `error` is the established coarse class for an illegal state change
  --     (`invalid_transition`, as the order state machine already uses) and `detail` is the
  --     established fine-grained safe token (as order_has_completed_payment already is).
  --     `order_status` is a STATE, never an identifier — safe to return.
  --
  --     AUDITED like the other two RETURN-based denials in this function
  --     (order.void_denied + denied_reason). A raise could not have audited at all: it
  --     would have rolled the audit row back. NO state change, NO revision bump, NO
  --     order_operations ledger row (denials are re-audited as probe attempts, never
  --     replayed).
  if v_o_status not in ('submitted', 'accepted', 'preparing', 'ready', 'served') then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.void_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
      jsonb_build_object('attempted_action', 'void_order', 'order_id', p_order_id,
                         'order_code', '#' || upper(right(replace(p_order_id::text, '-', ''), 6)),
                         'role', v_role, 'order_status', v_o_status,
                         'denied_reason', 'order_not_voidable'));
    return jsonb_build_object('ok', false, 'error', 'invalid_transition',
                              'detail', 'order_not_voidable', 'order_id', p_order_id,
                              'order_status', v_o_status,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (g2) RF-062 COMPLETED-PAYMENT GUARD (D-023/D-024; STATE_MACHINES §1; API_CONTRACT
  --      §4.6): an order with a LIVE `completed` payment cannot be voided in MVP — there
  --      is no refund/reversal flow. Checked AFTER authorization, reason, the idempotency
  --      replay, expected_revision, and state legality, BEFORE any mutation, so: a prior
  --      successful void still replays at (e) (a voided order can never acquire a
  --      completed payment afterward — record_payment rejects non-eligible orders); a
  --      genuinely terminal status is still refused at (g), which now RETURNS the typed
  --      domain refusal (invalid_transition + detail=order_not_voidable + order_status)
  --      rather than raising an untyped 42501 — so the two refusals stay DISTINGUISHABLE
  --      to the client; and only a
  --      legal-source order that nonetheless carries settled money reaches here. The
  --      order row is locked FOR UPDATE (b) and record_payment also locks it, so a
  --      concurrent payment cannot slip in. A4/A5/A3 decisions: block ONLY a live
  --      `completed` payment (deleted_at IS NULL; no method filter — any completed
  --      payment blocks); org-scoped to the session-derived v_org (tenant-safe); AUDIT
  --      `order.void_denied` (denied_reason=order_has_completed_payment) + RETURN a
  --      permission_denied envelope (NO raise — a raise would roll back the audit), with
  --      NO state change to order/order_items/payment and NO order_operations ledger row
  --      (denials are re-audited as probe attempts on retry, never replayed).
  if exists (
    select 1
    from public.payments p
    where p.organization_id = v_org
      and p.order_id = p_order_id
      and p.status = 'completed'
      and p.deleted_at is null
  ) then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.void_denied', nullif(btrim(coalesce(p_reason, '')), ''), null,
      jsonb_build_object('attempted_action', 'void_order', 'order_id', p_order_id,
                         'role', v_role, 'order_status', v_o_status,
                         'denied_reason', 'order_has_completed_payment'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied',
                              'detail', 'order_has_completed_payment', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (h) mutate: order -> voided (+reason, +revision); cascade items -> voided.
  --     PSC-001D: the SAME statement stamps the void PROVENANCE — when it
  --     happened, which state it was in, and whether the kitchen must
  --     acknowledge (an ACTIVE kitchen source: submitted|accepted|preparing|
  --     ready; a served-source void is already off the board). The
  --     acknowledgement triple stays NULL until app.kitchen_ack_void.
  v_new_rev := v_o_rev + 1;
  update public.orders
    set status = 'voided', void_reason = p_reason, revision = v_new_rev,
        voided_at = now(),
        voided_from_status = v_o_status,
        kitchen_ack_required = (v_o_status in ('submitted', 'accepted', 'preparing', 'ready'))
    where id = p_order_id;

  update public.order_items
    set status = 'voided', void_reason = p_reason
    where order_id = p_order_id and organization_id = v_org
      and status not in ('voided', 'cancelled');
  get diagnostics v_voided_items = row_count;

  -- (i) audit (order.voided) with old/new values (D-013). PSC-001D adds the two
  --     safe provenance scalars (a closed status enum + a boolean — never money,
  --     never an identifier; T-003 holds).
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch, null, v_emp, p_device_id,
    'order.voided', p_reason,
    jsonb_build_object('status', v_o_status, 'revision', v_o_rev),
    jsonb_build_object('status', 'voided', 'revision', v_new_rev,
                       'void_reason', p_reason, 'voided_item_count', v_voided_items,
                       'resolved_membership_id', v_membership,
                       'voided_from_status', v_o_status,
                       'kitchen_ack_required', (v_o_status in ('submitted', 'accepted', 'preparing', 'ready'))));

  -- (j) record ledger + return
  v_result := jsonb_build_object('ok', true, 'order_id', p_order_id, 'status', 'voided', 'revision', v_new_rev);
  insert into public.order_operations (organization_id, restaurant_id, branch_id, device_id, local_operation_id, action, order_id, result)
    values (v_org, v_rest, v_branch, p_device_id, p_local_operation_id, 'void_order', p_order_id, v_result);
  return v_result || jsonb_build_object('server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.void_order(uuid, uuid, uuid, text, text, integer) is
  'RF-053 + RF-062 + STAFF-CASHIER-PERMISSIONS-001 + MONEY-SETTLEMENT-CONSISTENCY-001 + PSC-001D (API_CONTRACT §4.6, D-011/D-024): SECURITY DEFINER RPC voiding a WRONG, UNPAID order with a MANDATORY reason. PIN-session auth; manager/restaurant_owner/org_owner, or a cashier with an explicit void_order capability. ELIGIBILITY IS UNCHANGED: legal source states are exactly submitted/accepted/preparing/ready/served — `completed` is TERMINAL (D-024) and there is NO completed -> void path, for a zero-total order or any other. A LIVE COMPLETED payment blocks the void (RF-062; no refund flow, D-023). Order row locked FOR UPDATE (serializes with record_payment). ALL THREE refusals are RETURNED, never raised (a raise would roll back the audit row) and are audited order.void_denied with a safe denied_reason: permission_denied (role), permission_denied + detail=order_has_completed_payment (paid), and invalid_transition + detail=order_not_voidable + order_status (terminal / illegal source state). Returning rather than raising is what lets app.sync_push propagate the domain code to the client verbatim — a RAISE is flattened to a generic ''rejected'', which previously left the POS unable to tell an already-closed order apart from a dropped network. Order-bound idempotency (D-022). Success cascades items -> voided and writes order.voided (D-013). PSC-001D: the success mutate ALSO stamps voided_at + voided_from_status and computes kitchen_ack_required (TRUE for an ACTIVE kitchen source submitted|accepted|preparing|ready; FALSE from served) so the KDS keeps the cancellation visible until app.kitchen_ack_void; the success audit carries the two safe provenance scalars. MONEY-FREE: creates/deletes NO payment and recomputes NO total.';

-- ACL parity for the UNCHANGED signature (CREATE OR REPLACE preserves grants;
-- re-issued explicitly per the submit_order recreation convention).
revoke all on function app.void_order(uuid, uuid, uuid, text, text, integer) from public;
revoke all on function app.void_order(uuid, uuid, uuid, text, text, integer) from anon;
grant execute on function app.void_order(uuid, uuid, uuid, text, text, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. app.kitchen_ack_void — the kitchen's explicit cancellation acknowledgement.
--    Reached ONLY via app.sync_push ('order.void_ack'); no public wrapper.
-- ----------------------------------------------------------------------------
create function app.kitchen_ack_void(
  p_pin_session_id     uuid,
  p_order_id           uuid,
  p_device_id          uuid,
  p_local_operation_id text
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
  v_device_type text;
  v_role        text;
  v_m_status    text;
  v_m_deleted   timestamptz;
  v_o_status    text;
  v_o_rev       integer;
  v_required    boolean;
  v_acked_at    timestamptz;
  v_from_status text;
  v_new_rev     integer;
  v_order_code  text := '#' || upper(right(replace(p_order_id::text, '-', ''), 6));
begin
  -- (a) THE CANONICAL PIN-SESSION PREAMBLE (identical to app.void_order). Every
  --     structural failure — bad session, expired, revoked device, wrong device,
  --     dead membership — raises an indistinguishable 42501 (RISK R-003).
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'kitchen_ack_void: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'kitchen_ack_void: PIN session is not valid' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'kitchen_ack_void: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'kitchen_ack_void: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'kitchen_ack_void: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) load the order FOR UPDATE through ONE query that carries every
  --     authoritative scope predicate (id + the session's org, restaurant AND
  --     branch). A nonexistent order and a foreign-scope order are therefore
  --     the LITERALLY IDENTICAL structural raise — same SQLSTATE, same
  --     message, no differing detail — because SQLERRM is persisted as the
  --     sync ledger's rejection_reason and later surfaced through the
  --     operation_statuses feed; two different messages would let a device
  --     probe whether a foreign order EXISTS (anti-oracle, R-003). The row
  --     lock serializes concurrent acknowledgements (and the void itself).
  select o.status, o.revision,
         o.kitchen_ack_required, o.kitchen_ack_at, o.voided_from_status
    into v_o_status, v_o_rev, v_required, v_acked_at, v_from_status
    from public.orders o
    where o.id              = p_order_id
      and o.organization_id = v_org
      and o.restaurant_id   = v_rest
      and o.branch_id       = v_branch
    for update;
  if not found then
    raise exception 'kitchen_ack_void: order_not_found_or_not_accessible' using errcode = '42501';
  end if;

  -- (c) KDS-CLASS DEVICE ONLY (locked decision). The device type comes from the
  --     SERVER's device row behind the session — never the client. A POS device
  --     is refused REGARDLESS of role, so the cashier who voided the order can
  --     never clear the kitchen safeguard from the POS. Audited + RETURNED (a
  --     raise would roll the audit back).
  select d.device_type into v_device_type
    from public.devices d where d.id = v_ds_device;
  if coalesce(v_device_type, '') <> 'kds' then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.void_ack_denied', null, null,
      jsonb_build_object('attempted_action', 'kitchen_ack_void', 'order_id', p_order_id,
                         'order_code', v_order_code, 'role', v_role,
                         'device_type', coalesce(v_device_type, 'unknown'),
                         'order_status', v_o_status,
                         'denied_reason', 'invalid_device_type'));
    return jsonb_build_object('ok', false, 'error', 'invalid_device_type', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (d) role gate (locked decision): the kitchen-class set. A cashier — even on
  --     a KDS device — is denied. Audited + RETURNED.
  if v_role not in ('kitchen_staff', 'manager', 'restaurant_owner', 'org_owner') then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.void_ack_denied', null, null,
      jsonb_build_object('attempted_action', 'kitchen_ack_void', 'order_id', p_order_id,
                         'order_code', v_order_code, 'role', v_role,
                         'device_type', v_device_type,
                         'order_status', v_o_status,
                         'denied_reason', 'permission_denied'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (e) state legality — flat typed codes (locked decision; the
  --     order_not_chargeable precedent). Both are audited + RETURNED so the KDS
  --     can name exactly what happened.
  if v_o_status <> 'voided' then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.void_ack_denied', null, null,
      jsonb_build_object('attempted_action', 'kitchen_ack_void', 'order_id', p_order_id,
                         'order_code', v_order_code, 'role', v_role,
                         'device_type', v_device_type,
                         'order_status', v_o_status,
                         'denied_reason', 'order_not_voided'));
    return jsonb_build_object('ok', false, 'error', 'order_not_voided', 'order_id', p_order_id,
                              'order_status', v_o_status,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;
  if not v_required then
    insert into public.audit_events (
      organization_id, restaurant_id, branch_id,
      actor_app_user_id, actor_employee_profile_id, device_id,
      action, reason, old_values, new_values)
    values (
      v_org, v_rest, v_branch, null, v_emp, p_device_id,
      'order.void_ack_denied', null, null,
      jsonb_build_object('attempted_action', 'kitchen_ack_void', 'order_id', p_order_id,
                         'order_code', v_order_code, 'role', v_role,
                         'device_type', v_device_type,
                         'order_status', v_o_status,
                         'denied_reason', 'acknowledgement_not_required'));
    return jsonb_build_object('ok', false, 'error', 'acknowledgement_not_required', 'order_id', p_order_id,
                              'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (f) ALREADY ACKNOWLEDGED — the DOMAIN idempotency (one branch-wide
  --     acknowledgement). A duplicate/late/concurrent attempt replays SUCCESS
  --     with already_acknowledged=true: NO second write, NO second audit, no
  --     revision bump. Transport-level replay of the SAME op is additionally
  --     deduped by the sync_operations ledger.
  if v_acked_at is not null then
    return jsonb_build_object(
      'ok', true, 'entity', 'order', 'order_id', p_order_id,
      'order_code', v_order_code,
      'acknowledged', true, 'already_acknowledged', true,
      'revision', v_o_rev,
      'server_ts', now(), 'idempotency_replay', false);
  end if;

  -- (g) FIRST acknowledgement: the write-once triple + a revision bump so the
  --     RF-052 updated_at trigger re-delivers the row through every KDS cursor
  --     (the red card clears branch-wide on the next pull).
  v_new_rev := v_o_rev + 1;
  update public.orders
    set kitchen_ack_at = now(),
        kitchen_ack_by_employee_profile_id = v_emp,
        kitchen_ack_device_id = p_device_id,
        revision = v_new_rev
    where id = p_order_id;

  -- (h) audit order.void_acknowledged (D-013): safe scalars only — a closed
  --     status enum, a role, a device class and the safe order code. Never
  --     money, never a foreign identifier (T-003).
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch, null, v_emp, p_device_id,
    'order.void_acknowledged', null,
    jsonb_build_object('order_id', p_order_id, 'revision', v_o_rev),
    jsonb_build_object('order_id', p_order_id, 'order_code', v_order_code,
                       'voided_from_status', v_from_status,
                       'kitchen_ack_required', true,
                       'role', v_role, 'device_type', v_device_type,
                       'revision', v_new_rev,
                       'local_operation_id', p_local_operation_id,
                       'resolved_membership_id', v_membership));

  return jsonb_build_object(
    'ok', true, 'entity', 'order', 'order_id', p_order_id,
    'order_code', v_order_code,
    'acknowledged', true, 'already_acknowledged', false,
    'revision', v_new_rev,
    'server_ts', now(), 'idempotency_replay', false);
end;
$$;

comment on function app.kitchen_ack_void(uuid, uuid, uuid, text) is
  'PSC-001D (D-011/D-013, RISK R-003): SECURITY DEFINER acknowledgement of a voided order by the KITCHEN. One successful acknowledgement clears the KDS red cancellation card for the WHOLE branch. Reached ONLY via app.sync_push (''order.void_ack''); no public wrapper. LOCKED enforcement, all server-side: valid PIN session + active backing device session/pairing + exact device match (structural 42501), the ORDER must be in the session''s exact org+branch (anti-oracle 42501 — a foreign/nonexistent order is indistinguishable), the session DEVICE must be device_type=''kds'' (a POS device is refused regardless of role — the voiding cashier can never clear the safeguard), and the role must be kitchen_staff|manager|restaurant_owner|org_owner (cashier denied). Expected refusals are FLAT TYPED RETURNS after a safe order.void_ack_denied audit: invalid_device_type | permission_denied | order_not_voided | acknowledgement_not_required. IDEMPOTENT: an already-acknowledged order replays success (already_acknowledged=true) with NO second write and NO second audit; the order row FOR UPDATE serializes concurrent attempts. Success stamps the write-once triple (kitchen_ack_at / by employee / by device), bumps orders.revision (the updated_at trigger re-delivers through every KDS pull cursor) and writes order.void_acknowledged. MONEY-FREE.';

revoke all on function app.kitchen_ack_void(uuid, uuid, uuid, text) from public;
revoke all on function app.kitchen_ack_void(uuid, uuid, uuid, text) from anon;
grant execute on function app.kitchen_ack_void(uuid, uuid, uuid, text) to authenticated;

-- ----------------------------------------------------------------------------
-- 4. Transport op-type CHECK (+order.void_ack = op #13) + app.sync_push
--    CREATE OR REPLACE (faithful re-creation of the 20260720110000 body + ONE
--    dispatch branch). All 12 prior operations preserved verbatim.
-- ----------------------------------------------------------------------------
alter table public.sync_operations drop constraint if exists sync_operations_operation_type_check;
alter table public.sync_operations add constraint sync_operations_operation_type_check
  check (operation_type in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink', 'order.void_ack'));

create or replace function app.sync_push(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_operations     jsonb
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
  v_op           jsonb;
  v_local_op     text;
  v_op_type      text;
  v_payload      jsonb;
  v_depends      jsonb;
  v_target_ent   text;
  v_target_id    uuid;
  v_client_ts    timestamptz;
  v_fingerprint  text;
  v_dep          text;
  v_dep_ok       boolean;
  v_ex_status    text;
  v_ex_result    jsonb;
  v_ex_optype    text;
  v_ex_fp        text;
  v_so_id        uuid;
  v_dispatch     jsonb;
  v_dispatch_ok  boolean;
  v_caught_state text;
  v_caught_msg   text;
  v_results      jsonb := '[]'::jsonb;
  v_op_result    jsonb;
  v_device_revoked boolean := false;
  v_customer_name text;
  v_ack_order    uuid;
  v_ack_ok       boolean;
begin
  -- (0) batch shape + a conservative size cap (no frozen limit in docs; 100 is the
  --     interim cap, surfaced here and in the tests — keeps a push transaction bounded).
  if p_operations is null or jsonb_typeof(p_operations) <> 'array' then
    raise exception 'sync_push: p_operations must be a JSON array' using errcode = '42501';
  end if;
  if jsonb_array_length(p_operations) > 100 then
    raise exception 'sync_push: batch too large (max 100 operations, got %)', jsonb_array_length(p_operations) using errcode = '42501';
  end if;

  -- (a) PIN session + backing device session/pairing. Scope is derived here. The PIN
  --     session must exist + be valid (offline-window bounded, Q-009); a missing session
  --     or expired PIN still raises (cannot key/record safely without a session/window).
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'sync_push: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'sync_push: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found then
    raise exception 'sync_push: backing device session not found' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'sync_push: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  -- RF061-A1: a REVOKED / inactive device session or pairing no longer fails the whole
  -- batch with a silent raise. Instead each pushed op is RECORDED as rejected
  -- (revoked_device) and surfaced, so the offline-queued operations are not lost (R-007;
  -- AC1). Authorization is INGEST-TIME (the device is revoked NOW); client timestamps are
  -- never trusted. A previously-APPLIED op still replays its stored result (idempotency).
  if not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    v_device_revoked := true;
    for v_op in select * from jsonb_array_elements(p_operations)
    loop
      v_local_op   := v_op ->> 'local_operation_id';
      v_op_type    := v_op ->> 'operation_type';
      v_payload    := v_op -> 'payload';
      v_depends    := coalesce(v_op -> 'depends_on', '[]'::jsonb);
      v_target_ent := v_op ->> 'target_entity';
      -- PSC-001D correction (F3): for order.void_ack the target id is parsed
      -- inside a PROTECTED boundary — a malformed uuid must reject only ITS
      -- operation, never abort the whole batch. The 12 prior operations keep
      -- their exact existing parse semantics.
      if v_op_type = 'order.void_ack' then
        begin
          v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
        exception when others then
          v_target_id := null;
        end;
      else
        v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
      end if;
      v_client_ts  := nullif(v_op ->> 'client_created_at', '')::timestamptz;

      -- envelope validation (same as the valid path): malformed -> rejected result, NO ledger row
      if v_local_op is null or btrim(v_local_op) = '' then
        v_results := v_results || jsonb_build_object('ok', false, 'error', 'invalid_envelope',
          'detail', 'local_operation_id is required', 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
      if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink', 'order.void_ack') then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'ok', false,
          'error', 'unknown_operation_type', 'detail', coalesce(v_op_type, '<null>'), 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
      if v_payload is null or jsonb_typeof(v_payload) <> 'object' then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
          'ok', false, 'error', 'invalid_payload', 'detail', 'payload must be a JSON object', 'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;

      -- PSC-001D correction (F2): the SAME conditional fingerprint as the
      -- valid path, so a legitimately-applied order.void_ack still replays
      -- its stored result after a revocation (identical identity -> identical
      -- fingerprint), while the 12 prior operations are unchanged.
      if v_op_type = 'order.void_ack' then
        v_fingerprint := md5(v_op_type || '|' || v_payload::text || '|' || coalesce(v_target_id::text, ''));
      else
        v_fingerprint := md5(v_op_type || '|' || v_payload::text);
      end if;

      -- dedup/replay: a stored op with the SAME identity that is TERMINAL replays its
      -- result (a legitimately-APPLIED op before revocation is NOT re-rejected); a
      -- different identity is a conflict; otherwise record the op as rejected (revoked_device).
      select so.status, so.result, so.operation_type, so.payload_fingerprint
        into v_ex_status, v_ex_result, v_ex_optype, v_ex_fp
        from public.sync_operations so
        where so.organization_id = v_org and so.device_id = p_device_id and so.local_operation_id = v_local_op;
      if found then
        if v_ex_optype <> v_op_type or v_ex_fp <> v_fingerprint then
          insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
          values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_conflict', null, null,
                  jsonb_build_object('local_operation_id', v_local_op, 'stored_operation_type', v_ex_optype, 'pushed_operation_type', v_op_type,
                                     'stored_status', v_ex_status, 'reason', 'idempotency_key_reused_with_different_operation_or_payload'));
          v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
            'error', 'conflict', 'detail', 'idempotency key already used for a different operation/payload', 'status', 'conflict', 'idempotency_replay', false);
          continue;
        end if;
        if v_ex_status in ('applied', 'rejected', 'dead', 'conflict') then
          v_results := v_results || (coalesce(v_ex_result, '{}'::jsonb)
            || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', v_ex_status, 'idempotency_replay', true));
          continue;
        end if;
      end if;

      -- record the op as rejected (revoked_device); NO business mutation, NO dispatch.
      insert into public.sync_operations as so (
        organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type,
        target_entity, target_id, payload, payload_fingerprint, depends_on, status,
        last_error_code, last_error_class, rejection_reason,
        result, client_created_at)
      values (v_org, v_rest, v_branch, p_device_id, v_local_op, v_op_type,
              v_target_ent, v_target_id, v_payload, v_fingerprint, v_depends, 'rejected',
              'revoked_device', 'permanent', 'revoked_device',
              jsonb_build_object('ok', false, 'error', 'rejected', 'detail', 'revoked_device'), v_client_ts)
      on conflict (organization_id, device_id, local_operation_id) do update
        set status = 'rejected', last_error_code = 'revoked_device', last_error_class = 'permanent',
            rejection_reason = 'revoked_device',
            result = jsonb_build_object('ok', false, 'error', 'rejected', 'detail', 'revoked_device'),
            retry_count = so.retry_count + 1, updated_at = now();
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected', 'revoked_device', null,
              jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'reason', 'revoked_device'));
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
        'error', 'rejected', 'detail', 'revoked_device', 'status', 'rejected', 'idempotency_replay', false);
    end loop;
    return jsonb_build_object('ok', true, 'results', v_results, 'server_ts', now(), 'device_revoked', true);
  end if;

  -- (b) per-operation loop (ordered) — VALID device path (unchanged from RF-056)
  for v_op in select * from jsonb_array_elements(p_operations)
  loop
    v_caught_state := null;
    v_caught_msg   := null;
    v_dispatch     := null;
    v_dispatch_ok  := null;
    v_so_id        := null;

    v_local_op   := v_op ->> 'local_operation_id';
    v_op_type    := v_op ->> 'operation_type';
    v_payload    := v_op -> 'payload';
    v_depends    := coalesce(v_op -> 'depends_on', '[]'::jsonb);
    v_target_ent := v_op ->> 'target_entity';
    -- PSC-001D correction (F3): protected parse for order.void_ack — a
    -- malformed target uuid rejects only ITS operation (below), never the
    -- batch. The 12 prior operations keep their exact existing semantics.
    if v_op_type = 'order.void_ack' then
      begin
        v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
      exception when others then
        v_target_id := null;
      end;
    else
      v_target_id := nullif(v_op ->> 'target_id', '')::uuid;
    end if;
    v_client_ts  := nullif(v_op ->> 'client_created_at', '')::timestamptz;

    -- (b1) envelope shape validation. Malformed envelopes are returned rejected
    --      WITHOUT a ledger row (they cannot be keyed/stored safely); they never dispatch.
    if v_local_op is null or btrim(v_local_op) = '' then
      v_results := v_results || jsonb_build_object('ok', false, 'error', 'invalid_envelope',
        'detail', 'local_operation_id is required', 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;
    if v_op_type is null or v_op_type not in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink', 'order.void_ack') then
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'ok', false,
        'error', 'unknown_operation_type', 'detail', coalesce(v_op_type, '<null>'), 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;
    if v_payload is null or jsonb_typeof(v_payload) <> 'object' then
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
        'ok', false, 'error', 'invalid_payload', 'detail', 'payload must be a JSON object', 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;
    if jsonb_typeof(v_depends) <> 'array' then
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
        'ok', false, 'error', 'invalid_depends_on', 'detail', 'depends_on must be a JSON array', 'status', 'rejected', 'idempotency_replay', false);
      continue;
    end if;

    -- (b1+) PSC-001D correction (F2/F3): CANONICAL TARGET IDENTITY for
    -- order.void_ack, enforced BEFORE the fingerprint, the terminal-replay
    -- lookup and the dispatch. The envelope MUST carry a parseable target_id
    -- AND a parseable payload.order_id and they MUST be the same uuid — a
    -- missing, malformed or CONTRADICTORY pair is a hostile/malformed
    -- envelope: rejected with NO ledger row (the malformed-envelope
    -- convention), so a replayed local_operation_id with a swapped target can
    -- never reach the stored terminal result, mutate anything, or learn
    -- anything about another order. Only this operation is affected.
    if v_op_type = 'order.void_ack' then
      v_ack_ok := v_target_id is not null;
      begin
        v_ack_order := nullif(v_payload ->> 'order_id', '')::uuid;
      exception when others then
        v_ack_order := null;
      end;
      if v_ack_order is null or not v_ack_ok or v_target_id <> v_ack_order then
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type,
          'ok', false, 'error', 'invalid_payload',
          'detail', 'order.void_ack requires matching uuid target_id and payload.order_id',
          'status', 'rejected', 'idempotency_replay', false);
        continue;
      end if;
    end if;

    -- PSC-001D correction (F2): the order.void_ack fingerprint BINDS the
    -- canonical order target identity, so a terminal replay is valid only for
    -- the same local_operation_id + operation + payload + TARGET. The 12
    -- prior operations keep their exact existing fingerprint semantics.
    if v_op_type = 'order.void_ack' then
      v_fingerprint := md5(v_op_type || '|' || v_payload::text || '|' || v_target_id::text);
    else
      v_fingerprint := md5(v_op_type || '|' || v_payload::text);
    end if;

    -- (b2) dedup / replay (transport identity = org + device + local_operation_id).
    select so.status, so.result, so.operation_type, so.payload_fingerprint
      into v_ex_status, v_ex_result, v_ex_optype, v_ex_fp
      from public.sync_operations so
      where so.organization_id = v_org and so.device_id = p_device_id and so.local_operation_id = v_local_op;
    if found then
      if v_ex_optype <> v_op_type or v_ex_fp <> v_fingerprint then
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_conflict', null, null,
                jsonb_build_object('local_operation_id', v_local_op, 'stored_operation_type', v_ex_optype, 'pushed_operation_type', v_op_type,
                                   'stored_status', v_ex_status, 'reason', 'idempotency_key_reused_with_different_operation_or_payload'));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'conflict', 'detail', 'idempotency key already used for a different operation/payload', 'status', 'conflict', 'idempotency_replay', false);
        continue;
      end if;
      if v_ex_status in ('applied', 'rejected', 'dead', 'conflict') then
        v_results := v_results || (coalesce(v_ex_result, '{}'::jsonb)
          || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', v_ex_status, 'idempotency_replay', true));
        continue;
      end if;
    end if;

    -- (b3) dependency guard.
    v_dep_ok := true;
    for v_dep in select jsonb_array_elements_text(v_depends)
    loop
      if not exists (
        select 1 from public.sync_operations so
        where so.organization_id = v_org and so.device_id = p_device_id
          and so.local_operation_id = v_dep and so.status = 'applied'
      ) then
        v_dep_ok := false;
        exit;
      end if;
    end loop;

    if not v_dep_ok then
      insert into public.sync_operations as so (
        organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type,
        target_entity, target_id, payload, payload_fingerprint, depends_on, status,
        last_error_code, last_error_class, client_created_at)
      values (v_org, v_rest, v_branch, p_device_id, v_local_op, v_op_type,
              v_target_ent, v_target_id, v_payload, v_fingerprint, v_depends, 'pending',
              'dependency_not_ready', 'transient', v_client_ts)
      on conflict (organization_id, device_id, local_operation_id) do update
        set status = 'pending', last_error_code = 'dependency_not_ready', last_error_class = 'transient',
            retry_count = so.retry_count + 1, updated_at = now();
      v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
        'error', 'dependency_not_ready', 'retryable', true, 'status', 'pending', 'idempotency_replay', false);
      continue;
    end if;

    -- (b4) mark in_flight (insert new, or bump a re-attempt)
    insert into public.sync_operations as so (
      organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type,
      target_entity, target_id, payload, payload_fingerprint, depends_on, status, client_created_at)
    values (v_org, v_rest, v_branch, p_device_id, v_local_op, v_op_type,
            v_target_ent, v_target_id, v_payload, v_fingerprint, v_depends, 'in_flight', v_client_ts)
    on conflict (organization_id, device_id, local_operation_id) do update
      set status = 'in_flight', retry_count = so.retry_count + 1, updated_at = now()
    returning so.id into v_so_id;

    -- (b5) dispatch to the matching business RPC inside a per-op EXCEPTION subtransaction.
    begin
      case v_op_type
        when 'shift.open' then
          v_dispatch := app.open_shift(
            p_pin_session_id,
            (v_payload ->> 'shift_id')::uuid,
            (v_payload ->> 'cash_drawer_session_id')::uuid,
            p_device_id,
            v_local_op,
            (v_payload ->> 'opening_float_minor')::bigint);
        when 'order.submit' then
          v_dispatch := app.submit_order(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'order_type',
            nullif(v_payload ->> 'table_id', '')::uuid,
            nullif(v_payload ->> 'shift_id', '')::uuid,
            v_payload ->> 'currency_code',
            v_payload ->> 'notes',
            v_payload -> 'order_items',
            (v_payload ->> 'subtotal_minor')::bigint,
            (v_payload ->> 'discount_total_minor')::bigint,
            (v_payload ->> 'tax_total_minor')::bigint,
            (v_payload ->> 'grand_total_minor')::bigint,
            v_client_ts);
          -- ORDER-CUSTOMER-001: stamp the OPTIONAL customer display name on the
          -- order app.submit_order just created. Kept OUT of submit_order so its
          -- validated INSERT stays byte-unchanged. Money-free display text: trim
          -- + empty->null + 80-char cap. Tenant-scoped by v_org; the
          -- `customer_name is null` guard makes it idempotent (a replay returns
          -- the same order_id, already stamped) and never overwrites.
          v_customer_name := left(btrim(coalesce(v_payload ->> 'customer_name', '')), 80);
          if v_customer_name <> '' then
            update public.orders
              set customer_name = v_customer_name
              where id = (v_dispatch ->> 'order_id')::uuid
                and organization_id = v_org
                and customer_name is null;
          end if;
        when 'order.discount' then
          v_dispatch := app.apply_discount(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'scope',
            nullif(v_payload ->> 'order_item_id', '')::uuid,
            v_payload ->> 'discount_type',
            (v_payload ->> 'value')::bigint,
            v_payload ->> 'reason',
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'payment.create' then
          v_dispatch := app.record_payment(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'tender_type',
            (v_payload ->> 'amount_tendered_minor')::bigint,
            nullif(v_payload ->> 'provisional_receipt_number', ''),
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'shift.close' then
          v_dispatch := app.close_shift(
            p_pin_session_id,
            (v_payload ->> 'shift_id')::uuid,
            p_device_id,
            v_local_op,
            (v_payload ->> 'counted_amount_minor')::bigint,
            nullif(v_payload ->> 'reason', ''),
            nullif(v_payload ->> 'expected_revision', '')::integer);
        -- MVP addition: KDS/POS order-status updates ride the SAME outbox/ledger
        -- (D-010/D-022). Scope/actor come from the pin session + device passed
        -- through (A8); the payload contributes ONLY {order_id, new_status}.
        when 'order.status' then
          v_dispatch := app.update_order_status(
            p_pin_session_id,
            p_device_id,
            (v_payload ->> 'order_id')::uuid,
            v_payload ->> 'new_status',
            v_local_op);
        when 'order.void' then
          -- MONEY-VOID-001: role-gated void of a wrong UNPAID order. Mirrors the
          -- order.discount branch - actor/org/branch come from the PIN session
          -- (never the payload) and the op's local_operation_id threads
          -- app.void_order's own idempotency (D-022). app.void_order (RF-053,
          -- hardened by RF-062) enforces manager/restaurant_owner/org_owner (or a
          -- cashier with permissions.void_order='true'), a mandatory reason, legal
          -- source states (submitted/accepted/preparing/ready/served), and the
          -- completed-payment block (an order with a live completed payment
          -- returns permission_denied) - so paid orders are refused server-side.
          -- Money-free: it only sets orders.status='voided' + void_reason +
          -- revision and cascades items -> voided; no payment/total is touched.
          v_dispatch := app.void_order(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            v_payload ->> 'reason',
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'order.table_move' then
          -- RESTAURANT-OPERATIONS-V1-001: atomic dine-in table move. Mirrors the
          -- order.void branch — actor/org/branch come from the PIN session
          -- (never the payload); the op's local_operation_id threads
          -- app.move_order_table's ORDER-BOUND idempotency (D-022); the payload
          -- contributes ONLY {order_id, table_id[, expected_revision]}. Typed
          -- refusals (table_not_allowed / invalid_transition+order_not_movable /
          -- table_not_available / permission_denied) RETURN through verbatim;
          -- a revision conflict raises 40001 -> the per-op 'conflict' status.
          -- Money-free: only orders.table_id + revision move.
          v_dispatch := app.move_order_table(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op,
            nullif(v_payload ->> 'table_id', '')::uuid,
            nullif(v_payload ->> 'expected_revision', '')::integer);
        when 'menu.availability_set' then
          -- PILOT-OPERATIONS-CORRECTIONS-001: a cashier (default-ON
          -- manage_menu_availability) or manager+ sets a menu item's per-branch
          -- availability from the POS. Actor/org/branch derive from the PIN
          -- session (NEVER the payload); the capability is enforced inside. The
          -- payload contributes ONLY {menu_item_id, availability, reason}. The
          -- setter is naturally idempotent (no-change re-applies the same state
          -- with no audit) and transport dedup (sync_operations) guards replay.
          -- Typed RETURN refusals (permission_denied / not_found) survive
          -- verbatim. MONEY-FREE.
          v_dispatch := app.pos_set_item_availability(
            p_pin_session_id,
            p_device_id,
            (v_payload ->> 'menu_item_id')::uuid,
            v_payload ->> 'availability',
            nullif(v_payload ->> 'reason', ''));
        when 'table.status_set' then
          -- PILOT-OPERATIONS-CORRECTIONS-001: manual table floor-state from the
          -- POS (manage_table_operations). Scope/actor from the session; payload
          -- {table_id, status}. Typed refusals survive verbatim. MONEY-FREE.
          v_dispatch := app.pos_set_table_status(
            p_pin_session_id, p_device_id,
            (v_payload ->> 'table_id')::uuid,
            v_payload ->> 'status');
        when 'table.link' then
          -- Link two same-branch tables into an operational group (no order/bill
          -- merge). Payload {table_id_a, table_id_b}. Deterministic lock order.
          v_dispatch := app.pos_link_tables(
            p_pin_session_id, p_device_id,
            (v_payload ->> 'table_id_a')::uuid,
            (v_payload ->> 'table_id_b')::uuid);
        when 'table.unlink' then
          -- Dissolve the group a table belongs to (orders untouched). Payload
          -- {table_id}.
          v_dispatch := app.pos_unlink_tables(
            p_pin_session_id, p_device_id,
            (v_payload ->> 'table_id')::uuid);
        when 'order.void_ack' then
          -- PSC-001D: the kitchen's cancellation acknowledgement. Mirrors the
          -- order.status branch — actor/org/branch come from the PIN session
          -- (never the payload); the payload contributes ONLY {order_id}.
          -- app.kitchen_ack_void enforces the KDS-class device, the kitchen
          -- role set, the voided + ack-required state, and the idempotent
          -- already-acknowledged replay; its flat typed refusals
          -- (invalid_device_type / permission_denied / order_not_voided /
          -- acknowledgement_not_required) RETURN through verbatim. TARGET-ID
          -- CONSISTENCY is enforced at (b1+) BEFORE the fingerprint and the
          -- terminal replay — by the time this arm runs, target_id and
          -- payload.order_id are guaranteed present, valid and equal. The
          -- check below is pure defence-in-depth and unreachable. MONEY-FREE.
          if v_target_id is null
             or v_target_id <> (v_payload ->> 'order_id')::uuid then
            raise exception 'sync_push: order.void_ack target_id does not match payload.order_id' using errcode = '42501';
          end if;
          v_dispatch := app.kitchen_ack_void(
            p_pin_session_id,
            (v_payload ->> 'order_id')::uuid,
            p_device_id,
            v_local_op);
      end case;
      v_dispatch_ok := coalesce((v_dispatch ->> 'ok')::boolean, false);
    exception
      when others then
        v_caught_state := SQLSTATE;
        v_caught_msg   := SQLERRM;
    end;

    -- (b6) finalize the operation outcome
    if v_caught_state is not null then
      if v_caught_state = '40001' then
        update public.sync_operations
          set status = 'conflict', last_error_code = v_caught_state, last_error_class = 'conflict',
              conflict_info = jsonb_build_object('sqlstate', v_caught_state, 'message', v_caught_msg),
              result = jsonb_build_object('ok', false, 'error', 'conflict', 'sqlstate', v_caught_state), updated_at = now()
          where id = v_so_id;
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_conflict', v_caught_msg, null,
                jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'sqlstate', v_caught_state));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'conflict', 'sqlstate', v_caught_state, 'status', 'conflict', 'idempotency_replay', false);
      else
        -- validation / state / business-rule failure -> permanent rejected. RF-061: a
        -- revoked-MEMBERSHIP op fails membership-active in the dispatched RPC; classify its
        -- rejection reason as 'revoked_employee' so the offline-revoked-employee case is clear.
        update public.sync_operations
          set status = 'rejected', last_error_code = v_caught_state, last_error_class = 'permanent',
              rejection_reason = case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee' else v_caught_msg end,
              result = jsonb_build_object('ok', false, 'error', 'rejected', 'sqlstate', v_caught_state,
                         'detail', case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee' else null end), updated_at = now()
          where id = v_so_id;
        insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
        values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected',
                case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee' else v_caught_msg end, null,
                jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'sqlstate', v_caught_state));
        v_results := v_results || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'ok', false,
          'error', 'rejected', 'sqlstate', v_caught_state,
          'detail', case when v_caught_msg ilike '%resolved membership is not active%' then 'revoked_employee' else null end,
          'status', 'rejected', 'idempotency_replay', false);
      end if;
    elsif v_dispatch_ok then
      update public.sync_operations
        set status = 'applied', result = v_dispatch, applied_at = now(),
            target_id = coalesce(v_target_id, nullif(v_dispatch ->> 'order_id', '')::uuid, nullif(v_dispatch ->> 'shift_id', '')::uuid, nullif(v_dispatch ->> 'payment_id', '')::uuid),
            updated_at = now()
        where id = v_so_id;
      v_results := v_results || (v_dispatch
        || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', 'applied', 'idempotency_replay', false));
    else
      update public.sync_operations
        set status = 'rejected', last_error_code = coalesce(v_dispatch ->> 'error', 'rejected'), last_error_class = 'permanent',
            rejection_reason = coalesce(v_dispatch ->> 'error', 'rejected'), result = v_dispatch, updated_at = now()
        where id = v_so_id;
      insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, v_emp, p_device_id, 'sync.operation_rejected', coalesce(v_dispatch ->> 'error', 'rejected'), null,
              jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'error', coalesce(v_dispatch ->> 'error', 'rejected')));
      v_results := v_results || (v_dispatch
        || jsonb_build_object('local_operation_id', v_local_op, 'operation_type', v_op_type, 'status', 'rejected', 'idempotency_replay', false));
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'results', v_results, 'server_ts', now());
end;
$$;

comment on function app.sync_push(uuid, uuid, jsonb) is
  'RF-056/RF-061 + ... + PILOT-OPERATIONS-CORRECTIONS-001 + PSC-001D (D-010/D-022) SECURITY DEFINER batch push. Faithful re-creation of the 20260720110000 body + ONE added dispatch branch: order.void_ack -> app.kitchen_ack_void (PIN session + KDS-class device + kitchen role set enforced inside; payload carries only order_id). ORDER.VOID_ACK IDENTITY HARDENING (independent-review corrections): the target uuid is parsed inside a PROTECTED per-operation boundary (a malformed target rejects only its own operation, never the batch); the envelope must carry a matching uuid target_id + payload.order_id (a missing/malformed/contradictory pair is a malformed envelope — rejected with NO ledger row, BEFORE the fingerprint and the terminal-replay lookup); and the operation''s fingerprint BINDS the canonical target identity, so a terminal replay is valid only for the same local_operation_id + type + payload + target. The 12 prior operations keep their exact parse/fingerprint semantics. All prior behaviour verbatim (batch cap, revoked-device recording, dedup/replay, dependency guard, per-op subtransactions, finalization, customer_name stamp). Authorization INGEST-TIME; scope from the session, never the payload.';

-- ACL parity (CREATE OR REPLACE preserves grants; re-issued explicitly).
revoke all on function app.sync_push(uuid, uuid, jsonb) from public;
revoke all on function app.sync_push(uuid, uuid, jsonb) from anon;
grant execute on function app.sync_push(uuid, uuid, jsonb) to authenticated;

-- ----------------------------------------------------------------------------
-- 5. app.audit_safe_detail — CREATE OR REPLACE (faithful 20260720110000 body)
--    with THREE additive safe scalar keys: voided_from_status (closed status
--    enum), device_type (closed pos|kds enum) and kitchen_ack_required
--    (boolean). Never money, never identifiers (T-003 holds).
--    app.audit_action_has_detail is NOT touched: the existing `order.void%`
--    family already detail-enables order.void_acknowledged and
--    order.void_ack_denied. app.audit_category is NOT touched: `order.void%`
--    already classifies both into `voids`.
-- ----------------------------------------------------------------------------
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
    'completion_mode','completion_trigger',
    -- MONEY-SETTLEMENT-CONSISTENCY-001: WHY a mutation was denied. order.discount_denied
    -- and order.void_denied have always carried this, but it was never allowlisted — so
    -- the Activity Log showed THAT a discount was refused and never WHY. It is a closed
    -- enum of safe STATE tokens (order_has_completed_payment | full_comp_requires_manager),
    -- never money and never an identifier (T-003 holds).
    'denied_reason',
    -- FULL-COMP-PERMISSION-001: WHAT the mutation would have left the order as. A
    -- closed enum of STATE tokens ('not_chargeable') -- never money, never an
    -- identifier (T-003 holds).
    'resulting_charge_state',
    -- RESTAURANT-OPERATIONS-V1-001: branch availability (closed enums
    -- available|unavailable / sold_out|paused) + the menu item's display name,
    -- and table-move floor labels (human table names). Names/labels are tenant
    -- display text already shown on receipts/tickets — never money, never ids.
    'availability','availability_reason','item_name',
    'table_label','from_table_label','to_table_label',
    -- PILOT-OPERATIONS-CORRECTIONS-001: manual table status transition
    -- (closed enum available|reserved|occupied|out_of_service) + the combined
    -- group label (floor names). Never money, never identifiers (T-003 holds).
    'from_status','to_status','group_label',
    -- PSC-001D: void provenance + kitchen acknowledgement. voided_from_status
    -- is the closed order-status enum; device_type is the closed pos|kds enum;
    -- kitchen_ack_required is a boolean. Never money, never identifiers
    -- (T-003 holds).
    'voided_from_status','device_type','kitchen_ack_required'
  ] loop
    if p_values ? v_key
       and jsonb_typeof(p_values -> v_key) in ('string','number','boolean') then
      v_out := v_out || jsonb_build_object(v_key, p_values -> v_key);
    end if;
  end loop;

  -- The ONLY allowlisted nested object: `capabilities`, kept to its four
  -- canonical boolean capability keys (unknown nested keys dropped).
  if jsonb_typeof(p_values -> 'capabilities') = 'object' then
    select coalesce(jsonb_object_agg(k, p_values -> 'capabilities' -> k), '{}'::jsonb)
      into v_caps
      from unnest(array['apply_discount','void_order','close_shift','apply_full_comp','manage_menu_availability','manage_table_operations']) as k
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
  'ALLOWLIST projection of one audit payload to canonical safe fields + PSC-001D: also emits voided_from_status (closed order-status enum), device_type (closed pos|kds enum) and kitchen_ack_required (boolean) -- never money, never identifiers (T-003 holds). Every un-listed key/structure dropped; malformed -> ''{}''; never throws.';

-- ============================================================================
-- DOWN (manual; Supabase is forward-only -- `supabase db reset` replays):
--   restore app.sync_push + app.audit_safe_detail from 20260720110000;
--   restore app.void_order from 20260716090000;
--   drop function if exists app.kitchen_ack_void(uuid, uuid, uuid, text);
--   restore sync_operations_operation_type_check without order.void_ack;
--   alter table public.orders
--     drop constraint if exists orders_kitchen_ack_device_fkey,
--     drop constraint if exists orders_kitchen_ack_employee_fkey,
--     drop constraint if exists orders_kitchen_ack_state_check,
--     drop constraint if exists orders_kitchen_ack_required_check,
--     drop constraint if exists orders_void_provenance_check,
--     drop constraint if exists orders_voided_from_status_check,
--     drop column if exists kitchen_ack_device_id,
--     drop column if exists kitchen_ack_by_employee_profile_id,
--     drop column if exists kitchen_ack_at,
--     drop column if exists kitchen_ack_required,
--     drop column if exists voided_from_status,
--     drop column if exists voided_at;
-- ============================================================================
