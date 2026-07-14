-- ============================================================================
-- POS-OPERATIONS-SYNC-001 -- server-authoritative POS order reconciliation
-- ============================================================================
-- The POS has never had an authoritative READ for a persisted order. It records
-- what it SUBMITTED and then never hears from the server again, so every
-- server-side change -- a discount, a payment, a KDS bump, an auto-completion, a
-- void -- is invisible to it. In production that shows up as an order the server
-- COMPLETED for zero (Dashboard: "No charge") still sitting on the POS with its
-- old total, an old non-terminal status, and payment/cancel buttons that cannot
-- possibly work.
--
-- This migration adds the missing READ.
--
-- (An EARLIER draft of this migration also carried the repair of the broken
-- app.pin_session_capabilities. That repair now ships SEPARATELY and EARLIER, in
-- 20260717120000_pin_session_capabilities_hotfix_001.sql, because production needed
-- it immediately and it must not wait on this phase. Keeping a second copy here
-- would be ACTIVELY HARMFUL, not merely redundant: this file sorts AFTER the
-- hotfix, so its older, less-hardened body would OVERWRITE the hotfix on every
-- fresh migrate and silently re-introduce the defect. The hotfix is the SINGLE
-- authoritative owner of that function.)
--
-- ---------------------------------------------------------------------------
-- app.pos_order_snapshots: the authoritative POS order read.
-- ---------------------------------------------------------------------------
-- WHY NOT EXTEND app.sync_pull. sync_pull already exists, is cursor-based, and is
-- PIN/device-scoped -- it was the obvious candidate. It is the wrong one:
--   * It is the KDS's feed too (packages/sync KdsSyncCoordinator) and its
--     row shape is a SHARED contract (packages/data_remote SyncPullResponse).
--     CLAUDE.md forbids folding a shared-package/API-contract change into a
--     feature ticket.
--   * It returns RAW rows (`to_jsonb(t)`) -- every column, including ones the POS
--     must not receive -- and it computes NOTHING. The POS would have to pull the
--     payments table too and re-derive settlement CLIENT-side, which is exactly
--     the duplicated-settlement-logic this phase exists to delete.
-- So this is a NEW, NARROW, POS-only read with an EXPLICIT column list and a
-- SERVER-COMPUTED settlement state. sync_pull is left completely untouched.
--
-- SETTLEMENT IS COMPUTED SERVER-SIDE, ONCE, SET-BASED. payment_status is
-- paid | unpaid | not_chargeable, using the SAME rule as app.order_is_fully_settled
-- (D-025): zero total => not_chargeable (owes nothing, carries no payment row);
-- positive total => paid only when a live completed payment COVERS it; negative
-- total => FAIL CLOSED to unpaid (a money defect must stay visible, not be hidden
-- behind a "No charge" badge). There is NO N+1: public.payments carries
-- `payments_one_completed_per_order_uidx` -- a UNIQUE partial index guaranteeing AT
-- MOST ONE completed payment per order -- so coverage is a plain LEFT JOIN on that
-- index, not a per-row aggregate or a correlated subquery.
--
-- THE SYNC STAMP IS NOT orders.updated_at. A payment does NOT touch the order row
-- (app.record_payment inserts into payments and only updates orders when
-- auto-completion fires), so an order that was PAID but not auto-completed changes
-- its settlement WITHOUT bumping orders.updated_at. A cursor over orders.updated_at
-- alone would silently never deliver it -- which is production failure #1. The
-- cursor therefore pages on
--     sync_at = greatest(orders.updated_at, completed_payment.updated_at)
-- with `id` as the tiebreak, so a payment is a real, orderable change.
--
-- BOUNDED BY THE POS OPERATIONAL WINDOW, NOT ALL HISTORY. Rows are restricted to
-- orders CREATED within p_window_days (default 2 = today + yesterday, matching the
-- POS's own local prune window). This is deliberate: the POS is an operational
-- surface, not an archive, and the phase forbids downloading the full history on
-- every refresh. It also means the scan is served by the EXISTING
-- `orders_history_keyset_idx (organization_id, branch_id, created_at DESC, id DESC)
-- WHERE deleted_at IS NULL` -- no new index is added, because none is warranted.
--
-- READ-ONLY. Mutates nothing. Writes NO audit event: opening a screen, polling, or
-- reconciling is not an operational action (a read is not a write, and an audit
-- trail that logs reads is an audit trail nobody can read).
--
-- Forward-only, additive. NOT applied to hosted by this migration.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1. app.pos_order_snapshots -- the authoritative, branch-scoped POS order read.
--
--    THREE MODES, ONE CODE PATH. The two CURSORS are deliberately SEPARATE, because
--    they answer different questions and pointing one at the other loses data:
--
--      A. INCREMENTAL  p_since_at + p_since_id
--                      "What has CHANGED since I last looked?"
--                      ASCENDING (sync_at, id), strictly AFTER the cursor. The client
--                      persists this cursor; it only ever moves FORWARD.
--
--      B. WINDOW       p_before_at + p_before_id (or neither -> start at the NEWEST)
--                      "Show me the branch, newest first."
--                      DESCENDING (sync_at, id), strictly BEFORE the cursor.
--
--                      *** NEWEST-FIRST IS NOT A PREFERENCE, IT IS A CORRECTNESS
--                      REQUIREMENT. *** This mode used to page ASCENDING from the
--                      start of the window, which means the FIRST page returned the
--                      OLDEST rows. On a busy branch the cashier would be shown
--                      yesterday's breakfast while the order placed ninety seconds
--                      ago sat thousands of rows away, reachable only by draining the
--                      entire window -- and a client that gave up after N pages would
--                      NEVER see it, while still reporting a successful sync. Paging
--                      DESCENDING makes the newest order the first row of the first
--                      page, by construction, at any volume.
--
--      C. TARGETED     p_order_ids non-null -> exactly those orders (still
--                      branch-scoped). One authoritative snapshot after a specific
--                      write or a conflict. Cursors are ignored.
--
--    Both cursors keyset on (sync_at, id) with the ORDER ID as the tie-breaker, so
--    rows sharing a sync_at to the microsecond still page deterministically: no
--    duplicate, no skip, in either direction.
-- ---------------------------------------------------------------------------
create or replace function app.pos_order_snapshots(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_since_at       timestamptz default null,
  p_since_id       uuid        default null,
  p_before_at      timestamptz default null,
  p_before_id      uuid        default null,
  p_order_ids      uuid[]      default null,
  p_limit          integer     default 50,
  p_window_days    integer     default 2
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_org          uuid;
  v_branch       uuid;
  v_dsid         uuid;
  v_membership   uuid;
  v_ds_device    uuid;
  v_ds_active    boolean;
  v_ds_revoked   timestamptz;
  v_pairing      text;
  v_role         text;
  v_m_status     text;
  v_m_deleted    timestamptz;
  v_limit        integer;
  v_window_start timestamptz;
  v_rows         jsonb;
  v_count        integer;
  v_next_at      timestamptz;
  v_next_id      uuid;
  v_max_at       timestamptz;
  v_max_id       uuid;
  v_min_at       timestamptz;
  v_min_id       uuid;
  -- TRUE only for the INCREMENTAL change feed. The WINDOW pages DESCENDING.
  v_ascending    boolean;
begin
  -- (a) THE CANONICAL PIN-SESSION PREAMBLE (identical to app.apply_discount).
  --     Every failure -- bad session, expired, revoked device, wrong device,
  --     dead membership -- collapses to ONE indistinguishable envelope: a caller
  --     must not be able to probe WHICH check failed (RISK R-003).
  select ps.organization_id, ps.branch_id, ps.device_session_id, ps.resolved_membership_id
    into v_org, v_branch, v_dsid, v_membership
    from public.pin_sessions ps
    where ps.id = p_pin_session_id;
  if not found or not app.is_pin_session_valid(p_pin_session_id) then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'order_snapshot');
  end if;

  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found
     or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active')
     or v_ds_device is distinct from p_device_id then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'order_snapshot');
  end if;

  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m
    where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'order_snapshot');
  end if;

  -- (b) INPUT VALIDATION -- FAIL CLOSED. A malformed cursor is REFUSED, never
  --     silently coerced into "start from the beginning": quietly restarting the
  --     cursor would re-deliver the whole window and look like success.
  if (p_since_at is null) <> (p_since_id is null) then
    return jsonb_build_object('ok', false, 'error', 'invalid_cursor', 'entity', 'order_snapshot');
  end if;
  if (p_before_at is null) <> (p_before_id is null) then
    return jsonb_build_object('ok', false, 'error', 'invalid_cursor', 'entity', 'order_snapshot');
  end if;
  -- The two cursors are DIFFERENT QUESTIONS and must never be asked at once: an
  -- ascending "what changed" and a descending "show me older" cannot both be honoured
  -- by one page, and silently picking one would give the caller a page it did not ask
  -- for while advancing a cursor it did not mean to move.
  if p_since_at is not null and p_before_at is not null then
    return jsonb_build_object('ok', false, 'error', 'invalid_cursor', 'entity', 'order_snapshot');
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 100 then
    return jsonb_build_object('ok', false, 'error', 'invalid_limit', 'entity', 'order_snapshot');
  end if;
  if p_window_days is null or p_window_days < 1 or p_window_days > 14 then
    return jsonb_build_object('ok', false, 'error', 'invalid_window', 'entity', 'order_snapshot');
  end if;
  if p_order_ids is not null and array_length(p_order_ids, 1) > 100 then
    return jsonb_build_object('ok', false, 'error', 'invalid_limit', 'entity', 'order_snapshot');
  end if;
  v_limit        := p_limit;
  v_window_start := (now() at time zone 'utc')::date - make_interval(days => p_window_days - 1);

  -- MODE. Only an explicit `since` cursor asks the ASCENDING question ("what changed
  -- since I last looked"). Everything else -- including the very first, cursorless
  -- call -- is the WINDOW: newest first. That default is the whole fix. A cursorless
  -- call used to mean "ascend from the start of the window", which handed a busy
  -- branch its OLDEST rows and buried the newest order thousands of rows deep.
  v_ascending := (p_since_at is not null);

  -- (c) THE SNAPSHOT.
  --
  --     SCOPE: the PIN session's OWN organization_id AND branch_id, taken from the
  --     SERVER's session row -- never from anything the client sent. There is no
  --     parameter by which a caller could name another branch, restaurant or
  --     tenant, so a sibling-branch/sibling-restaurant/cross-tenant read is not
  --     "denied", it is UNREACHABLE.
  --
  --     SETTLEMENT: one LEFT JOIN on payments' UNIQUE partial index
  --     (payments_one_completed_per_order_uidx: at most ONE completed payment per
  --     order), so coverage is set-based -- no correlated subquery, no per-row
  --     aggregate, no N+1.
  --
  --     SYNC STAMP: greatest(o.updated_at, pay.updated_at). A payment does not
  --     touch the order row, so ordering on o.updated_at alone would never deliver
  --     a paid-but-not-yet-completed order to an incremental cursor.
  with scoped as (
    select
      o.id,
      o.status,
      o.revision,
      o.order_type,
      o.created_at,
      o.updated_at,
      o.subtotal_minor,
      o.discount_total_minor,
      o.tax_total_minor,
      o.grand_total_minor,
      o.currency_code,
      -- The table's human LABEL, never its internal UUID (T-003 forbids projecting
      -- an internal id). `notes` and `customer_name` are deliberately NOT selected:
      -- private order notes are explicitly out of the safe set, and the POS already
      -- holds the customer name it typed -- a reconciliation read has no reason to
      -- ship personal data back.
      tbl.label as table_label,
      pay.amount_minor as covered_minor,
      greatest(o.updated_at, coalesce(pay.updated_at, o.updated_at)) as sync_at
    from public.orders o
    left join public.tables tbl
      on  tbl.organization_id = o.organization_id
      and tbl.id              = o.table_id
    left join public.payments pay
      on  pay.organization_id = o.organization_id
      and pay.order_id        = o.id
      and pay.status          = 'completed'
      and pay.deleted_at is null
    where o.organization_id = v_org
      and o.branch_id       = v_branch
      and o.deleted_at is null
      -- TARGETED mode ignores the window: a snapshot requested for a SPECIFIC
      -- order after a write must return it even if it sits outside the window.
      and (p_order_ids is not null or o.created_at >= v_window_start)
      and (p_order_ids is null or o.id = any (p_order_ids))
  ),
  stamped as (
    select
      s.*,
      case
        when s.grand_total_minor < 0  then 'unpaid'            -- FAIL CLOSED (money defect stays visible)
        when s.grand_total_minor = 0  then 'not_chargeable'    -- owes nothing; carries no payment row
        when coalesce(s.covered_minor, 0) >= s.grand_total_minor then 'paid'
        else 'unpaid'
      end as payment_status
    from scoped s
  ),
  -- THE PAGE. `v_ascending` is TRUE only for the INCREMENTAL feed; the WINDOW pages
  -- DESCENDING so the NEWEST order is the first row of the first page, whatever the
  -- volume. Both directions keyset on (sync_at, id) -- the ORDER ID is the
  -- tie-breaker, so rows sharing a sync_at to the microsecond cannot be duplicated
  -- across pages or skipped between them.
  page as (
    select *
    from stamped st
    where p_order_ids is not null
       or (v_ascending
             and (p_since_at is null
                  or (st.sync_at, st.id) > (p_since_at, p_since_id)))
       or ((not v_ascending)
             and (p_before_at is null
                  or (st.sync_at, st.id) < (p_before_at, p_before_id)))
    order by
      case when v_ascending then st.sync_at end asc,
      case when v_ascending then st.id      end asc,
      case when not v_ascending then st.sync_at end desc,
      case when not v_ascending then st.id      end desc
    limit v_limit
  )
  select
    coalesce(jsonb_agg(
      jsonb_build_object(
        'order_id',             p.id,
        -- The SAFE public reference, never the raw UUID (T-003).
        'order_code',           '#' || upper(right(replace(p.id::text, '-', ''), 6)),
        'revision',             p.revision,
        'status',               p.status,
        'order_type',           p.order_type,
        'table_label',          p.table_label,
        'currency_code',        p.currency_code,
        'created_at',           p.created_at,
        'updated_at',           p.updated_at,
        'sync_at',              p.sync_at,
        'subtotal_minor',       p.subtotal_minor,
        'discount_total_minor', p.discount_total_minor,
        'tax_total_minor',      p.tax_total_minor,
        'grand_total_minor',    p.grand_total_minor,
        'payment_status',       p.payment_status
      ) order by
        case when v_ascending then p.sync_at end asc,
        case when v_ascending then p.id      end asc,
        case when not v_ascending then p.sync_at end desc,
        case when not v_ascending then p.id      end desc
    ), '[]'::jsonb),
    count(*)::integer,
    -- The cursor to RESUME from is the LAST row of this page in ITS OWN direction:
    -- the greatest (sync_at, id) when ascending, the least when descending.
    (array_agg(p.sync_at order by p.sync_at desc, p.id desc))[1],
    (array_agg(p.id      order by p.sync_at desc, p.id desc))[1],
    (array_agg(p.sync_at order by p.sync_at asc,  p.id asc))[1],
    (array_agg(p.id      order by p.sync_at asc,  p.id asc))[1]
  into v_rows, v_count, v_max_at, v_max_id, v_min_at, v_min_id
  from page p;

  if v_ascending then
    v_next_at := v_max_at;  -- resume AFTER the newest row we just took
    v_next_id := v_max_id;
  else
    v_next_at := v_min_at;  -- resume BEFORE the oldest row we just took
    v_next_id := v_min_id;
  end if;

  -- A page that filled the limit MAY have more behind it; a short page is the end.
  -- A caller must NEVER read "this bounded page did not contain order X" as "order
  -- X was deleted" -- the envelope says so explicitly by never claiming completeness.
  return jsonb_build_object(
    'ok',            true,
    'entity',        'order_snapshot',
    'server_ts',     now(),
    'window_start',  v_window_start,
    'orders',        v_rows,
    'has_more',      (v_count = v_limit and p_order_ids is null),
    'next_cursor',   case
                       when v_count = v_limit and p_order_ids is null
                       then jsonb_build_object('at', v_next_at, 'id', v_next_id)
                       else null
                     end);
end;
$$;

comment on function app.pos_order_snapshots(uuid, uuid, timestamptz, uuid, timestamptz, uuid, uuid[], integer, integer) is
  'POS-OPERATIONS-SYNC-001: the AUTHORITATIVE, branch-scoped POS order read. The POS previously had NONE -- it recorded what it SUBMITTED and never heard from the server again, so a discount, a payment, a KDS bump, an auto-completion or a void were all invisible to it (a server-completed zero-total order still sat on the POS with its old total and live payment/cancel buttons). SCOPE: the PIN session''s OWN organization_id + branch_id, taken from the SERVER''s session row -- there is NO parameter naming a branch/restaurant/tenant, so a sibling-branch or cross-tenant read is UNREACHABLE rather than merely denied. THREE MODES, one code path, with TWO SEPARATE CURSORS that must never be conflated: INCREMENTAL (p_since_at/p_since_id) pages ASCENDING for the durable changed-since feed; WINDOW (p_before_at/p_before_id, or neither) pages DESCENDING -- NEWEST FIRST -- for browsing the branch; TARGETED (p_order_ids) returns exactly those orders after a write or a conflict. NEWEST-FIRST IS A CORRECTNESS REQUIREMENT, NOT A PREFERENCE: the window used to page ASCENDING from the start, so on a busy branch the FIRST page returned the OLDEST rows and the order placed ninety seconds ago sat thousands of rows away -- a client that stopped after N pages would never reach it while still reporting a successful sync. Both directions keyset on (sync_at, id) with the ORDER ID as tie-breaker, so equal-timestamp rows page deterministically: no duplicate, no skip, either way. Asking BOTH cursors at once is refused (invalid_cursor). SETTLEMENT is computed SERVER-SIDE (paid | unpaid | not_chargeable) with the SAME rule as app.order_is_fully_settled (D-025) -- zero total => not_chargeable, positive => paid only when a live completed payment COVERS it, negative => FAIL CLOSED to unpaid so a money defect stays visible. NO N+1: payments_one_completed_per_order_uidx guarantees at most ONE completed payment per order, so coverage is a plain LEFT JOIN on a unique index. THE CURSOR PAGES ON greatest(orders.updated_at, payment.updated_at), NOT orders.updated_at -- app.record_payment does not touch the order row, so a paid-but-not-auto-completed order changes its settlement without bumping orders.updated_at and an orders-only cursor would never deliver it. Bounded to the POS operational window (default today+yesterday) and served by the EXISTING orders_history_keyset_idx -- no new index. A malformed cursor/limit/window is REFUSED (fail closed), never coerced into a silent full restart. Money is integer minor units (D-007). Returns only SAFE fields -- no customer contact data, no notes, no internal staff UUIDs, no payment-processor detail, no raw metadata; the order is identified by the safe #XXXXXX code. READ-ONLY: mutates nothing and writes NO audit event (opening a screen, polling and reconciling are not operational actions).';


-- ---------------------------------------------------------------------------
-- 2. public wrapper -- the PostgREST-reachable entry point (the public.sync_push /
--    public.pin_session_capabilities pattern: anon key + PIN/device session).
-- ---------------------------------------------------------------------------
create or replace function public.pos_order_snapshots(
  p_pin_session_id uuid,
  p_device_id      uuid,
  p_since_at       timestamptz default null,
  p_since_id       uuid        default null,
  p_before_at      timestamptz default null,
  p_before_id      uuid        default null,
  p_order_ids      uuid[]      default null,
  p_limit          integer     default 50,
  p_window_days    integer     default 2
)
  returns jsonb
  language sql
  volatile
  security invoker
  set search_path = ''
as $$
  select app.pos_order_snapshots(p_pin_session_id, p_device_id, p_since_at,
                                 p_since_id, p_before_at, p_before_id,
                                 p_order_ids, p_limit, p_window_days);
$$;

comment on function public.pos_order_snapshots(uuid, uuid, timestamptz, uuid, timestamptz, uuid, uuid[], integer, integer) is
  'POS-OPERATIONS-SYNC-001: PUBLIC (PostgREST-reachable) INVOKER wrapper over app.pos_order_snapshots -- the POS reaches it with the anon key plus its PIN/device session, exactly like public.sync_push. Carries no authority of its own.';


-- ---------------------------------------------------------------------------
-- 3. ACLs. Revoked from PUBLIC and anon; `authenticated` only. No service-role
--    grant (D-011). The anon revoke is MANDATORY: hosted Supabase''s
--    ALTER DEFAULT PRIVILEGES grants EXECUTE to anon on every new public function
--    at CREATE time, so a wrapper that only revokes from PUBLIC keeps an anon grant.
-- ---------------------------------------------------------------------------
revoke all on function app.pos_order_snapshots(uuid, uuid, timestamptz, uuid, timestamptz, uuid, uuid[], integer, integer) from public;
revoke all on function app.pos_order_snapshots(uuid, uuid, timestamptz, uuid, timestamptz, uuid, uuid[], integer, integer) from anon;
grant execute on function app.pos_order_snapshots(uuid, uuid, timestamptz, uuid, timestamptz, uuid, uuid[], integer, integer) to authenticated;

revoke all on function public.pos_order_snapshots(uuid, uuid, timestamptz, uuid, timestamptz, uuid, uuid[], integer, integer) from public;
revoke all on function public.pos_order_snapshots(uuid, uuid, timestamptz, uuid, timestamptz, uuid, uuid[], integer, integer) from anon;
grant execute on function public.pos_order_snapshots(uuid, uuid, timestamptz, uuid, timestamptz, uuid, uuid[], integer, integer) to authenticated;
