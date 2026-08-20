-- ============================================================================
-- KIOSK-001-PHASE2-DEVICE-AUTH-SECURITY-072 — kiosk device security foundation.
--
-- A customer self-service kiosk is a PAIRED, REVOCABLE DEVICE (D-005 #4) that
-- must let customers order WITHOUT an employee PIN session, while every staff
-- surface stays PIN-gated exactly as today. This migration is the SERVER
-- foundation only (the kiosk app stays fixture-only until its own phase):
--
--   1. devices.device_type gains 'kiosk' (additive; pos/kds rows untouched).
--   2. app.create_device + app.redeem_device_pairing re-emitted byte-faithfully
--      with 'kiosk' added to their type allowlists — kiosk devices use the SAME
--      single-use enrollment code, hash-only session token, expiry, restore and
--      revocation lifecycle as POS/KDS (RF-112/RF-161/RF-118; nothing relaxed).
--   3. audit_events_actor_present widened: a recorded DEVICE is now a valid
--      audit actor (owner decision A: the kiosk device IS the audited actor;
--      no fake employee, no service identity). Every existing writer still
--      records its human actor exactly as before.
--   4. orders.pin_session_id / opened_by_employee_profile_id /
--      resolved_membership_id become NULLABLE with an ALL-OR-NONE constraint:
--      a row carries the FULL staff actor triple (every existing/POS path,
--      unchanged) or NONE of it (kiosk-created orders only; the writing RPC is
--      the only path that can produce such a row — direct INSERT/UPDATE/DELETE
--      on orders remain revoked from clients since RF-052, and RLS stays FORCED).
--   5. sync_operations.operation_type gains 'kiosk.order.submit' so kiosk
--      submits reuse the SAME transport idempotency ledger (D-022) with the
--      SAME atomic claim / fingerprint / terminal-replay contract as sync_push.
--   6. Three narrow token-proven RPCs (device session token proof IDENTICAL to
--      app.restore_device_session, PLUS device_type = 'kiosk'):
--        app.kiosk_menu          — customer sell-menu projection (derived from
--                                  app.pos_menu's cashier branch; sku never
--                                  served; prep_minutes/kitchen_note/attributes/
--                                  default_station_id/sizes/variants omitted).
--        app.kiosk_tables        — zone/section + table + effective_state only
--                                  (derived from app.pos_tables; no manual
--                                  status, no occupancy counts, no floor
--                                  geometry, no group/order details).
--        app.kiosk_submit_order  — the ONE kiosk mutation. Validation blocks
--                                  are the app.submit_order blocks verbatim
--                                  (shape, currency, snapshot money recompute,
--                                  sellability under FOR UPDATE, 003D modifier
--                                  ownership, 021 frozen-prep comparison, the
--                                  KITCHEN-MODE dispatch/auto-complete tail),
--                                  with a KIOSK-ONLY atomic table gate (owner
--                                  decision B: NO TTL holds; the chosen table
--                                  row is LOCKED at submit and must be
--                                  effectively AVAILABLE — occupied/reserved/
--                                  out-of-service/foreign are refused with a
--                                  stable machine-readable error while POS
--                                  keeps its merge-parties power untouched).
--   7. public SECURITY INVOKER wrappers + exact grants (authenticated only;
--      never anon; never service_role — D-011/D-012).
--   8. HARDENING-FIX-073 (independent review): the kiosk client is UNTRUSTED —
--      unlike the staff POS, its snapshots carry no authority. kiosk_submit_order
--      therefore refuses: any price drift from the canonical live menu
--      (menu_price_changed — refresh, never silent repricing), any modifier
--      rule violation (modifier_selection_invalid — required/min/max/single/
--      quantity per the POS effective rules; dead/hidden selections), any
--      customer discount (discount_not_allowed), any non-tenant currency
--      (currency_mismatch), and any tax that is not the RF-117 branch-setting
--      computation (tax_mismatch). Persisted name snapshots are canonical DB
--      values; and a row trigger (orders_actor_guard) proves every actorless
--      order really belongs to a kiosk device.
--
-- NOT here (deliberately): table TTL holds (deferred by owner decision B), any
-- backfill or data change, fake employees/service identities, client wiring,
-- realtime-hint enablement for kiosks, storage-policy changes (menu-image
-- reads stay POS-only until the kiosk media phase), and the pre-existing
-- hosted public.* grant divergence cleanup (tracked separately).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. device_type 'kiosk' — the canonical device-type contract (rf016 CHECK).
--    The rf016 column CHECK is unnamed-inline (auto-named); drop defensively
--    by its default name and assert the replacement exists.
-- ----------------------------------------------------------------------------
alter table public.devices drop constraint if exists devices_device_type_check;
alter table public.devices add constraint devices_device_type_check
  check (device_type in ('pos', 'kds', 'kiosk'));

comment on column public.devices.device_type is
  'Device surface type: pos | kds | kiosk (KIOSK-001 Phase 2). INTERIM label set (ASSUMPTION; not in D-018). kiosk = a customer self-service device: same pairing/session/revocation lifecycle as pos/kds, but its token may only call the kiosk_* RPC family (no PIN-session mutations).';

-- ----------------------------------------------------------------------------
-- 2. app.create_device — the rf112 body VERBATIM with 'kiosk' allowed. Every
--    other line (ledger idempotency, rank gate, audit, NULL credential ref)
--    is byte-identical to the shipped definition.
-- ----------------------------------------------------------------------------
create or replace function app.create_device(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_branch_id         uuid,
  p_device_type       text,
  p_label             text default null
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
  v_id     uuid := gen_random_uuid();
  v_result jsonb;
  v_new    jsonb;
begin
  if v_actor is null then
    raise exception 'create_device: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'create_device: client_request_id is required' using errcode = '42501';
  end if;
  -- devices are branch-scoped (org/restaurant/branch NOT NULL); there is NO station column.
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    raise exception 'create_device: organization_id, restaurant_id and branch_id are required' using errcode = '42501';
  end if;
  if p_device_type is null or p_device_type not in ('pos', 'kds', 'kiosk') then
    raise exception 'create_device: device_type must be pos, kds or kiosk' using errcode = '42501';
  end if;
  -- target branch + parent restaurant must exist in the org AND be LIVE (not soft-deleted).
  if not exists (
       select 1 from public.branches b
       join public.restaurants r on r.id = b.restaurant_id and r.organization_id = b.organization_id
       where b.id = p_branch_id and b.organization_id = p_organization_id
         and b.restaurant_id = p_restaurant_id and b.deleted_at is null and r.deleted_at is null) then
    raise exception 'create_device: branch not found in organization/restaurant or scope is soft-deleted' using errcode = '42501';
  end if;

  v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id, 'branch', p_branch_id,
              'device_type', p_device_type, 'label', p_label)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'create_device', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'create_device: caller has no active membership covering the target scope' using errcode = '42501';
  end if;
  if v_rank < 2 then     -- cashier/kitchen_staff/accountant cannot provision
    perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id, 'device.create_denied', null,
      jsonb_build_object('device_type', p_device_type));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'device');
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'device', 'device_id', v_id);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'create_device', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  insert into public.devices (id, organization_id, restaurant_id, branch_id, device_type, label, is_active)
  values (v_id, p_organization_id, p_restaurant_id, p_branch_id, p_device_type, nullif(btrim(coalesce(p_label, '')), ''), true);
  -- device_credential_ref is left NULL: the real device credential is OS-secure-stored on the device
  -- and provisioned later (RF-021); no device secret is minted/returned at create time.

  select to_jsonb(t) into v_new from public.devices t where t.id = v_id;
  perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id, 'device.created', null, v_new);
  return v_result;
end;
$$;

comment on function app.create_device(uuid, uuid, uuid, uuid, text, text) is
  'RF-112 device registration (manager+ via the management idempotency ledger; no secret minted). KIOSK-001 Phase 2: the type allowlist gains ''kiosk'' — a kiosk registers, enrolls and revokes exactly like a POS/KDS device. Everything else byte-identical to the shipped rf112 definition.';

-- ----------------------------------------------------------------------------
-- 3. app.redeem_device_pairing — the rf118 body VERBATIM with 'kiosk' allowed
--    in the DECLARED-type allowlist. The device row's own type must still
--    match the declared type (wrong_type), the code is still single-use, the
--    lockout, expiry, prior-session revoke and hash-only token are untouched.
-- ----------------------------------------------------------------------------
create or replace function app.redeem_device_pairing(
  p_enrollment_code text,
  p_device_type     text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor      uuid := app.current_app_user_id();  -- null for an anonymous device (audit only)
  v_uid        uuid := auth.uid();                  -- RF-118: caller principal for the lockout
  v_locked     timestamptz;                         -- RF-118
  v_hash       text;
  v_pairing    uuid;
  v_org        uuid;
  v_rest       uuid;
  v_branch     uuid;
  v_device     uuid;
  v_expires    timestamptz;
  v_dtype      text;
  v_dactive    boolean;
  v_ddeleted   timestamptz;
  v_session    uuid := gen_random_uuid();
  v_token      text;
  v_token_hash text;
  v_rows       integer;
begin
  if p_enrollment_code is null or btrim(p_enrollment_code) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_code', 'entity', 'device_pairing');
  end if;
  if p_device_type is null or p_device_type not in ('pos', 'kds', 'kiosk') then
    return jsonb_build_object('ok', false, 'error', 'invalid_type', 'entity', 'device_pairing');
  end if;

  -- RF-118: per-principal brute-force lockout, checked BEFORE the expensive code
  -- hash + pairing lookup. A locked caller gets a SAFE generic 'locked' error
  -- (rate-limited != code exists), and no code lookup runs.
  if v_uid is not null then
    select s.locked_until into v_locked
      from public.device_pairing_attempt_states s
      where s.auth_user_id = v_uid;
    if v_locked is not null and v_locked > now() then
      return jsonb_build_object('ok', false, 'error', 'locked', 'entity', 'device_pairing');
    end if;
  end if;

  v_hash := app.hash_provisioning_secret(btrim(p_enrollment_code));

  -- redeemable pairing by code hash: code_issued + live + unrevoked. Scope is DERIVED here.
  select dp.id, dp.organization_id, dp.restaurant_id, dp.branch_id, dp.device_id, dp.code_expires_at
    into v_pairing, v_org, v_rest, v_branch, v_device, v_expires
    from public.device_pairings dp
    where dp.enrollment_code_hash = v_hash
      and dp.status = 'code_issued'
      and dp.revoked_at is null
      and dp.deleted_at is null
    order by dp.created_at desc
    limit 1;
  if v_pairing is null then
    perform app.note_pairing_failure(v_uid);  -- RF-118
    return jsonb_build_object('ok', false, 'error', 'invalid_code', 'entity', 'device_pairing');
  end if;
  if v_expires is not null and v_expires <= now() then
    perform app.note_pairing_failure(v_uid);  -- RF-118
    return jsonb_build_object('ok', false, 'error', 'expired', 'entity', 'device_pairing');
  end if;

  -- the device must be live on a LIVE branch/restaurant, and its declared type must match.
  select d.device_type, d.is_active, d.deleted_at
    into v_dtype, v_dactive, v_ddeleted
    from public.devices d
    join public.branches b on b.id = d.branch_id and b.organization_id = d.organization_id
      and b.restaurant_id = d.restaurant_id and b.deleted_at is null
    join public.restaurants r on r.id = d.restaurant_id and r.organization_id = d.organization_id
      and r.deleted_at is null
    where d.id = v_device and d.organization_id = v_org;
  if v_dtype is null or not v_dactive or v_ddeleted is not null then
    -- device or scope not live => invalid (fail closed; no scope leak).
    perform app.note_pairing_failure(v_uid);  -- RF-118
    return jsonb_build_object('ok', false, 'error', 'invalid_code', 'entity', 'device_pairing');
  end if;
  if v_dtype <> p_device_type then
    perform app.note_pairing_failure(v_uid);  -- RF-118
    return jsonb_build_object('ok', false, 'error', 'wrong_type', 'entity', 'device_pairing');
  end if;

  -- consume the code + activate the pairing (guarded; race-safe one-time redemption).
  update public.device_pairings
     set status = 'active', paired_at = now()
     where id = v_pairing and status = 'code_issued';
  get diagnostics v_rows = row_count;
  if v_rows = 0 then
    perform app.note_pairing_failure(v_uid);  -- RF-118
    return jsonb_build_object('ok', false, 'error', 'invalid_code', 'entity', 'device_pairing');
  end if;

  -- hygiene: one active session per device -> revoke any prior live sessions.
  update public.device_sessions
     set is_active = false, revoked_at = now()
     where device_id = v_device and revoked_at is null;

  -- mint the session: store ONLY the hash; return the raw token ONCE.
  -- MVP (menu/media sprint): also record auth_user_id = auth.uid() -- the storage
  -- device-read policy binding, PRESERVED here unchanged from mvp_menu_item_images
  -- (this migration REPLACES that newest redeem body; v_uid is that same auth.uid()).
  -- RF-118: additionally bound the session with expires_at = now() + the max age.
  v_token      := replace(gen_random_uuid()::text, '-', '');
  v_token_hash := app.hash_provisioning_secret(v_token);
  insert into public.device_sessions
    (id, organization_id, restaurant_id, branch_id, device_id, device_pairing_id, session_token_ref, is_active, auth_user_id, expires_at)
  values (v_session, v_org, v_rest, v_branch, v_device, v_pairing, v_token_hash, true,
          v_uid, now() + app.device_session_max_age());

  -- RF-118: a successful redemption clears the caller's failure counter.
  if v_uid is not null then
    delete from public.device_pairing_attempt_states where auth_user_id = v_uid;
  end if;

  -- audit ONLY when a human actor exists (audit_events requires a human actor; a device has none).
  if v_actor is not null then
    insert into public.audit_events
      (organization_id, restaurant_id, branch_id, actor_app_user_id, device_id, action, reason, old_values, new_values)
    values
      (v_org, v_rest, v_branch, v_actor, v_device, 'device.redeemed_by_code', null,
       jsonb_build_object('device_pairing_id', v_pairing, 'from', 'code_issued'),
       jsonb_build_object('device_pairing_id', v_pairing, 'device_session_id', v_session, 'status', 'active'));
  end if;

  return jsonb_build_object('ok', true, 'entity', 'device_session',
    'device_session_id', v_session, 'session_token', v_token,
    'organization_id', v_org, 'restaurant_id', v_rest, 'branch_id', v_branch,
    'device_id', v_device, 'device_type', v_dtype);
end;
$$;

comment on function app.redeem_device_pairing(text, text) is
  'RF-161 + RF-118 device-originated code redemption (see the rf118 comment for the full contract — lockout, single-use consume, hash-only token, expiry). KIOSK-001 Phase 2: the declared-type allowlist gains ''kiosk''; the device row''s own type must still match (wrong_type), so a kiosk code can only ever activate a kiosk device. Every other line byte-identical to the shipped rf118 definition.';

-- ----------------------------------------------------------------------------
-- 4. Audit actor contract (owner decision A): a recorded DEVICE becomes a
--    valid audit actor. Every existing writer keeps recording its human actor
--    (nothing else changed); the kiosk path records device-attributed events
--    (actor_kind='kiosk_device' inside new_values) with both human actor
--    columns NULL and device_id NOT NULL.
-- ----------------------------------------------------------------------------
alter table public.audit_events drop constraint if exists audit_events_actor_present;
alter table public.audit_events add constraint audit_events_actor_present
  check (actor_app_user_id is not null
      or actor_employee_profile_id is not null
      or device_id is not null);

comment on constraint audit_events_actor_present on public.audit_events is
  'D-013: an actor is always recorded. KIOSK-001 Phase 2 (owner decision A): a paired DEVICE is a valid actor — kiosk-path events carry device_id with both human actor columns NULL. Every staff/JWT path still records its human actor exactly as before.';

-- ----------------------------------------------------------------------------
-- 5. Kiosk order actor model (owner decision A): the staff actor triple
--    becomes NULLABLE with an ALL-OR-NONE boundary constraint. Existing rows
--    (all staff-created) satisfy the constraint unchanged; the POS path keeps
--    writing the full triple; only app.kiosk_submit_order writes the NULL
--    triple. Clients cannot forge either shape: INSERT/UPDATE/DELETE on
--    orders remain revoked (RF-052) and RLS remains enabled+forced.
-- ----------------------------------------------------------------------------
alter table public.orders alter column pin_session_id                drop not null;
alter table public.orders alter column opened_by_employee_profile_id drop not null;
alter table public.orders alter column resolved_membership_id        drop not null;

alter table public.orders add constraint orders_actor_all_or_none
  check (
    (pin_session_id is not null
      and opened_by_employee_profile_id is not null
      and resolved_membership_id is not null)
    or
    (pin_session_id is null
      and opened_by_employee_profile_id is null
      and resolved_membership_id is null)
  );

comment on constraint orders_actor_all_or_none on public.orders is
  'KIOSK-001 Phase 2 (owner decision A): an order carries the FULL staff actor triple (every PIN/POS path — unchanged) or NONE of it (kiosk-created orders; device_id is the audited actor). A partial triple is invalid in both worlds. Direct writes stay revoked; only the SECURITY DEFINER submit RPCs can produce rows.';

-- Defense-in-depth (HARDENING-FIX-073): the all-or-none CHECK cannot itself
-- prove an actorless row belongs to a KIOSK device. This row trigger closes
-- that: a NULL staff triple is only legal when the row device is
-- device_type='kiosk' (checked on INSERT and on any UPDATE, so a staff order
-- can never be laundered into an actorless one). The full-triple staff path
-- short-circuits without touching the devices table. SECURITY DEFINER so the
-- device lookup never depends on the writing role RLS view; 23514 keeps
-- constraint-violation semantics for callers and tests.
create function app.orders_actor_guard()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
begin
  if new.pin_session_id is null
     and new.opened_by_employee_profile_id is null
     and new.resolved_membership_id is null then
    if not exists (
         select 1 from public.devices d
           where d.id = new.device_id
             and d.organization_id = new.organization_id
             and d.device_type = 'kiosk') then
      raise exception 'orders: a staff-actorless order is only legal from a kiosk device'
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function app.orders_actor_guard() from public;

create trigger orders_actor_guard
  before insert or update on public.orders
  for each row execute function app.orders_actor_guard();

comment on function app.orders_actor_guard() is
  'KIOSK-001 HARDENING-FIX-073 defense-in-depth: a NULL staff actor triple on an order is only legal when the order''s device is a kiosk. Full-triple staff rows short-circuit (no lookup). 23514 = constraint semantics.';

-- ----------------------------------------------------------------------------
-- 6. Transport idempotency ledger: the kiosk submit op joins the SAME ledger
--    (D-022). Additive widening; every prior value survives.
-- ----------------------------------------------------------------------------
alter table public.sync_operations drop constraint if exists sync_operations_operation_type_check;
alter table public.sync_operations add constraint sync_operations_operation_type_check
  check (operation_type in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink', 'order.void_ack', 'order.items_add', 'order.round_status', 'kiosk.order.submit'));

-- ----------------------------------------------------------------------------
-- 7. app.kiosk_session_context — the ONE kiosk token proof. The liveness chain
--    is the app.restore_device_session chain VERBATIM (session token hash,
--    active + unrevoked + UNEXPIRED session, active pairing, active device,
--    live branch + restaurant) PLUS device_type = 'kiosk'. Returns NULLs when
--    anything fails — callers translate to their stable envelope. app-schema
--    internal: no public wrapper, no direct grant.
-- ----------------------------------------------------------------------------
create function app.kiosk_session_context(
  p_device_id     uuid,
  p_session_token text,
  out o_session   uuid,
  out o_org       uuid,
  out o_rest      uuid,
  out o_branch    uuid
)
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_hash text;
begin
  o_session := null; o_org := null; o_rest := null; o_branch := null;
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return;
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));
  select ds.id, ds.organization_id, ds.restaurant_id, ds.branch_id
    into o_session, o_org, o_rest, o_branch
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
      and (ds.expires_at is null or ds.expires_at > now())  -- RF-118: expired = refused
      and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null
      and d.is_active and d.deleted_at is null
      and d.device_type = 'kiosk';                          -- kiosk-only capability gate
end;
$$;

comment on function app.kiosk_session_context(uuid, text) is
  'KIOSK-001 Phase 2: the single kiosk token proof — the RF-118 restore_device_session liveness chain (hash-proven token, active+unexpired session, active pairing, active device, live branch/restaurant) PLUS device_type=''kiosk''. NULL outputs = refused (revoked, expired, wrong token, wrong device, non-kiosk type, dead scope). Scope is ALWAYS derived here, never from client input. app-internal: no public wrapper, no direct client grant.';

revoke all on function app.kiosk_session_context(uuid, text) from public;

-- ----------------------------------------------------------------------------
-- 8. app.kiosk_menu — the customer sell-menu projection. Derived from the
--    app.pos_menu cashier branch (ops044 definition): SAME live/branch-visible
--    predicates, SAME category/modifier shapes (icon_key included), SAME
--    tenant currency rule. Customer-narrowed: items omit default_station_id,
--    prep_minutes, kitchen_note and the attributes bag (kitchen internals);
--    sizes/variants are not served (runtime-dead legacy); sku was never
--    served to devices anywhere. modifier_options keep kitchen_meat so the
--    kiosk client can freeze the SAME prep snapshot the POS freezes (the 021
--    submit gate verifies it server-side).
-- ----------------------------------------------------------------------------
create function app.kiosk_menu(
  p_device_id     uuid,
  p_session_token text
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_sid        uuid;
  v_org        uuid;
  v_rest       uuid;
  v_branch     uuid;
  v_currency   text;
  v_categories jsonb;
  v_items      jsonb;
  v_modifiers  jsonb;
  v_options    jsonb;
begin
  select o_session, o_org, o_rest, o_branch
    into v_sid, v_org, v_rest, v_branch
    from app.kiosk_session_context(p_device_id, p_session_token);
  if v_sid is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kiosk_menu');
  end if;

  -- the REAL tenant currency: restaurants.currency_override, else the
  -- organization default (identical to app.pos_menu / app.list_menu).
  select coalesce(r.currency_override, o.default_currency)
    into v_currency
    from public.restaurants r
    join public.organizations o on o.id = r.organization_id
    where r.id = v_rest and r.organization_id = v_org;

  -- live categories of the session restaurant, branch-visible (pos_menu (d)).
  select coalesce(jsonb_agg(
           jsonb_build_object('id', c.id, 'name', c.name, 'display_order', c.display_order,
                              'icon_key', c.icon_key)
           order by c.display_order, c.name), '[]'::jsonb)
    into v_categories
    from public.menu_categories c
    where c.organization_id = v_org
      and c.restaurant_id = v_rest
      and c.is_active
      and c.deleted_at is null
      and (c.branch_id is null or c.branch_id = v_branch);

  -- live items with the pos_menu (e) predicates VERBATIM; customer-narrow keys.
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', i.id, 'menu_category_id', i.menu_category_id, 'name', i.name,
             'description', i.description, 'display_order', i.display_order,
             'item_type', i.item_type, 'tags', i.tags,
             'base_price_minor', i.base_price_minor,
             'image_path', i.image_path,
             'availability', coalesce(a.availability, 'available'),
             'availability_reason', a.reason)
           order by i.display_order, i.name), '[]'::jsonb)
    into v_items
    from public.menu_items i
    join public.menu_categories c
      on c.organization_id = i.organization_id
     and c.restaurant_id   = v_rest
     and c.id = i.menu_category_id
    left join public.menu_item_branch_availability a
      on a.organization_id = i.organization_id
     and a.branch_id       = v_branch
     and a.menu_item_id    = i.id
    where i.organization_id = v_org
      and i.restaurant_id = v_rest
      and i.is_active
      and i.deleted_at is null
      and (i.branch_id is null or i.branch_id = v_branch)
      and c.is_active
      and c.deleted_at is null
      and (c.branch_id is null or c.branch_id = v_branch);

  -- live modifiers of LIVE items (pos_menu (h) VERBATIM — money-free rows).
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', m.id, 'menu_item_id', m.menu_item_id, 'name', m.name,
             'selection_type', m.selection_type, 'min_select', m.min_select,
             'max_select', m.max_select, 'is_required', m.is_required,
             'allow_quantity', m.allow_quantity, 'max_quantity', m.max_quantity,
             'display_order', m.display_order)
           order by m.display_order, m.name), '[]'::jsonb)
    into v_modifiers
    from public.modifiers m
    join public.menu_items i
      on i.organization_id = m.organization_id
     and i.restaurant_id   = v_rest
     and i.id = m.menu_item_id
    join public.menu_categories c
      on c.organization_id = i.organization_id
     and c.restaurant_id   = v_rest
     and c.id = i.menu_category_id
    where m.organization_id = v_org
      and m.restaurant_id = v_rest
      and m.is_active
      and m.deleted_at is null
      and (m.branch_id is null or m.branch_id = v_branch)
      and i.is_active and i.deleted_at is null and (i.branch_id is null or i.branch_id = v_branch)
      and c.is_active and c.deleted_at is null and (c.branch_id is null or c.branch_id = v_branch);

  -- live options of LIVE modifiers (pos_menu (i) cashier branch VERBATIM).
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', mo.id, 'modifier_id', mo.modifier_id, 'name', mo.name,
             'display_order', mo.display_order,
             'price_delta_minor', mo.price_delta_minor, 'kitchen_meat', mo.kitchen_meat)
           order by mo.display_order, mo.name), '[]'::jsonb)
    into v_options
    from public.modifier_options mo
    join public.modifiers m
      on m.organization_id = mo.organization_id and m.id = mo.modifier_id
    join public.menu_items i
      on i.organization_id = m.organization_id
     and i.restaurant_id   = v_rest
     and i.id = m.menu_item_id
    join public.menu_categories c
      on c.organization_id = i.organization_id
     and c.restaurant_id   = v_rest
     and c.id = i.menu_category_id
    where mo.organization_id = v_org
      and mo.restaurant_id = v_rest
      and mo.is_active
      and mo.deleted_at is null
      and (mo.branch_id is null or mo.branch_id = v_branch)
      and m.is_active and m.deleted_at is null and (m.branch_id is null or m.branch_id = v_branch)
      and i.is_active and i.deleted_at is null and (i.branch_id is null or i.branch_id = v_branch)
      and c.is_active and c.deleted_at is null and (c.branch_id is null or c.branch_id = v_branch);

  return jsonb_build_object(
    'ok', true,
    'entity', 'kiosk_menu',
    'currency_code', v_currency,
    'categories', v_categories,
    'items', v_items,
    'modifiers', v_modifiers,
    'modifier_options', v_options,
    'server_ts', now());
end;
$$;

comment on function app.kiosk_menu(uuid, text) is
  'KIOSK-001 Phase 2: token-proven CUSTOMER sell-menu for a kiosk device (device_type=kiosk only; scope session-derived). The pos_menu cashier projection narrowed to ordering needs: categories(icon_key)/items(prices, image_path, availability)/modifier groups/options(deltas + kitchen_meat for the 021 frozen-prep contract). NEVER serves: sku, prep_minutes, kitchen_note, attributes, default_station_id, sizes, variants, staff/PIN/printer/audit data. invalid_session envelope on any proof failure.';

-- ----------------------------------------------------------------------------
-- 9. app.kiosk_tables — the customer floor read: zone/section + table +
--    effective state ONLY. Occupancy is DERIVED with the pos_tables (b)
--    subquery VERBATIM and folded through app.table_effective_state; the raw
--    manual status, counts, groups, layout geometry and floor fixtures are
--    NOT served (customers see the honest state, nothing else).
-- ----------------------------------------------------------------------------
create function app.kiosk_tables(
  p_device_id     uuid,
  p_session_token text
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_sid    uuid;
  v_org    uuid;
  v_rest   uuid;
  v_branch uuid;
  v_tables jsonb;
begin
  select o_session, o_org, o_rest, o_branch
    into v_sid, v_org, v_rest, v_branch
    from app.kiosk_session_context(p_device_id, p_session_token);
  if v_sid is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kiosk_tables');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'label', t.label, 'seats', t.seats, 'area', t.area,
           'section_id', t.section_id,
           'section_name', s.name,
           'section_display_order', s.display_order,
           'effective_state', app.table_effective_state(t.status, coalesce(oc.n, 0)))
           order by t.label, t.id), '[]'::jsonb)
    into v_tables
    from public.tables t
    left join public.table_sections s
      on s.id = t.section_id and s.organization_id = t.organization_id
     and s.deleted_at is null
    left join (
      select o.table_id, count(*)::int as n
        from public.orders o
        where o.organization_id = v_org
          and o.branch_id       = v_branch
          and o.order_type      = 'dine_in'
          and o.table_id is not null
          and o.deleted_at is null
          and o.status in ('submitted', 'accepted', 'preparing', 'ready', 'served')
        group by o.table_id
    ) oc on oc.table_id = t.id
    where t.organization_id = v_org
      and t.restaurant_id   = v_rest
      and t.branch_id       = v_branch
      and t.is_active
      and t.deleted_at is null;

  return jsonb_build_object(
    'ok', true,
    'entity', 'kiosk_tables',
    'tables', v_tables,
    'server_ts', now());
end;
$$;

comment on function app.kiosk_tables(uuid, text) is
  'KIOSK-001 Phase 2: token-proven CUSTOMER table read for a kiosk device (device_type=kiosk only; scope session-derived). Serves section/zone identity + label/seats + the canonical effective_state (app.table_effective_state over the pos_tables derived-occupancy subquery) — and NOTHING else: no manual status, no order counts, no customer/order details, no groups, no layout geometry, no fixtures. Display truth only; NO hold/claim happens here (owner decision B). invalid_session envelope on any proof failure.';

-- ----------------------------------------------------------------------------
-- 10. app.kiosk_submit_order — the ONE kiosk mutation. See the header block;
--     validation is app.submit_order's, actor is the kiosk DEVICE, the table
--     gate is the kiosk-only atomic AVAILABLE check, and the transport ledger
--     claim mirrors app.sync_push (b2) for op 'kiosk.order.submit'.
-- ----------------------------------------------------------------------------
create function app.kiosk_submit_order(
  p_device_id                   uuid,
  p_session_token               text,
  p_order_id                    uuid,
  p_local_operation_id          text,
  p_order_type                  text,
  p_table_id                    uuid,
  p_currency_code               text,
  p_notes                       text,
  p_customer_name               text,
  p_customer_phone              text,
  p_order_items                 jsonb,
  p_client_subtotal_minor       bigint,
  p_client_discount_total_minor bigint,
  p_client_tax_total_minor      bigint,
  p_client_grand_total_minor    bigint,
  p_client_created_at           timestamptz default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_sid           uuid;
  v_org           uuid;
  v_rest          uuid;
  v_branch        uuid;
  v_payload       jsonb;
  v_fingerprint   text;
  v_so_id         uuid;
  v_ex_id         uuid;
  v_ex_status     text;
  v_ex_result     jsonb;
  v_ex_optype     text;
  v_ex_fp         text;
  v_existing_id   uuid;
  v_existing_rev  integer;
  v_existing_status text;
  v_item          jsonb;
  v_modifier      jsonb;
  v_item_id       uuid;
  v_qty           bigint;
  v_unit          bigint;
  v_line_disc     bigint;
  v_mod_qty       bigint;
  v_mod_price     bigint;
  v_mod_sum       bigint;
  v_line_total    bigint;
  v_subtotal      bigint := 0;
  v_grand         bigint;
  v_item_count    integer := 0;
  v_mod_count     integer := 0;
  v_unavailable   jsonb;
  v_bad_modifiers jsonb;
  v_stale_modifiers jsonb;
  v_item_ids      uuid[];
  v_t_status      text;
  v_customer_name text;
  v_customer_phone text;
  v_kitchen_mode  text;
  v_canon_currency  text;
  v_tax_enabled     boolean;
  v_tax_rate_bp     integer;
  v_tax_mode        text;
  v_expected_tax    bigint;
  v_price_mismatch  jsonb;
  v_invalid_mods    jsonb;
  v_canon_item_name text;
  v_canon_mod_name  text;
  v_canon_opt_name  text;
  v_canon_delta     bigint;
  v_auto          jsonb;
  v_result        jsonb;
begin
  -- (proof) kiosk device session token — the ONLY authority. Scope is derived
  -- here; nothing scope-shaped is accepted from the payload (R-003).
  select o_session, o_org, o_rest, o_branch
    into v_sid, v_org, v_rest, v_branch
    from app.kiosk_session_context(p_device_id, p_session_token);
  if v_sid is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'order');
  end if;

  -- (protocol shape) identities the ledger + business replay key on.
  if p_order_id is null then
    raise exception 'kiosk_submit_order: order_id is required' using errcode = '42501';
  end if;
  if p_local_operation_id is null or btrim(p_local_operation_id) = '' then
    raise exception 'kiosk_submit_order: local_operation_id is required' using errcode = '42501';
  end if;

  -- (customer identity) OPTIONAL name/phone, validated UP FRONT exactly like
  -- sync_push's order.submit arm: an invalid non-empty phone is a typed
  -- refusal and no order is created; both values are display data only.
  v_customer_name  := left(btrim(coalesce(p_customer_name, '')), 80);
  v_customer_phone := btrim(coalesce(p_customer_phone, ''));
  if v_customer_phone <> '' and not app.is_valid_customer_phone(v_customer_phone) then
    return jsonb_build_object('ok', false, 'error', 'invalid_payload',
                              'entity', 'order', 'field', 'customer_phone');
  end if;

  -- (b2 mirror) ATOMIC transport-ledger claim (D-022), the sync_push contract
  -- verbatim for a single op: fingerprint EXCLUDES customer_phone (data-only —
  -- the same canonical rule as order.submit), claim is one INSERT .. ON
  -- CONFLICT DO NOTHING; a lost claim locks the committed row and either
  -- refuses a reused key (different payload), replays a TERMINAL result, or
  -- adopts a stale non-terminal row.
  v_payload := jsonb_build_object(
    'order_id', p_order_id, 'order_type', p_order_type, 'table_id', p_table_id,
    'currency_code', p_currency_code, 'notes', p_notes,
    'customer_name', nullif(v_customer_name, ''),
    'customer_phone', nullif(v_customer_phone, ''),
    'order_items', p_order_items,
    'subtotal_minor', p_client_subtotal_minor,
    'discount_total_minor', p_client_discount_total_minor,
    'tax_total_minor', p_client_tax_total_minor,
    'grand_total_minor', p_client_grand_total_minor);
  v_fingerprint := md5('kiosk.order.submit' || '|' || (v_payload - 'customer_phone')::text);

  insert into public.sync_operations as so (
    organization_id, restaurant_id, branch_id, device_id, local_operation_id, operation_type,
    target_entity, target_id, payload, payload_fingerprint, depends_on, status, client_created_at)
  values (v_org, v_rest, v_branch, p_device_id, btrim(p_local_operation_id), 'kiosk.order.submit',
          'order', p_order_id, v_payload, v_fingerprint, '[]'::jsonb, 'in_flight', p_client_created_at)
  on conflict (organization_id, device_id, local_operation_id) do nothing
  returning so.id into v_so_id;

  if v_so_id is null then
    select so.id, so.status, so.result, so.operation_type, so.payload_fingerprint
      into v_ex_id, v_ex_status, v_ex_result, v_ex_optype, v_ex_fp
      from public.sync_operations so
      where so.organization_id = v_org and so.device_id = p_device_id
        and so.local_operation_id = btrim(p_local_operation_id)
      for update;
    if v_ex_optype <> 'kiosk.order.submit' or v_ex_fp <> v_fingerprint then
      insert into public.audit_events (organization_id, restaurant_id, branch_id,
        actor_app_user_id, actor_employee_profile_id, device_id, action, reason, old_values, new_values)
      values (v_org, v_rest, v_branch, null, null, p_device_id, 'kiosk.operation_conflict', null, null,
              jsonb_build_object('actor_kind', 'kiosk_device',
                                 'local_operation_id', btrim(p_local_operation_id),
                                 'stored_operation_type', v_ex_optype,
                                 'pushed_operation_type', 'kiosk.order.submit',
                                 'stored_status', v_ex_status,
                                 'reason', 'idempotency_key_reused_with_different_operation_or_payload'));
      return jsonb_build_object('ok', false, 'error', 'conflict', 'entity', 'order',
        'detail', 'idempotency key already used for a different operation/payload');
    end if;
    if v_ex_status in ('applied', 'rejected', 'dead', 'conflict') then
      return coalesce(v_ex_result, '{}'::jsonb) || jsonb_build_object('idempotency_replay', true);
    end if;
    v_so_id := v_ex_id;  -- adopt the stale non-terminal row (crashed claimant)
  end if;

  -- (payload) basic shape + currency + order_type — submit_order VERBATIM.
  if p_order_items is null or jsonb_typeof(p_order_items) <> 'array' or jsonb_array_length(p_order_items) < 1 then
    raise exception 'kiosk_submit_order: order_items must be a non-empty jsonb array' using errcode = '42501';
  end if;
  if p_order_type not in ('dine_in', 'takeaway') then
    raise exception 'kiosk_submit_order: invalid order_type %', p_order_type using errcode = '42501';
  end if;
  if p_currency_code is null or p_currency_code !~ '^[A-Z]{3}$' then
    raise exception 'kiosk_submit_order: currency_code must be a 3-letter ISO code' using errcode = '42501';
  end if;
  if p_client_discount_total_minor < 0 or p_client_tax_total_minor < 0
     or p_client_subtotal_minor < 0 or p_client_grand_total_minor < 0 then
    raise exception 'kiosk_submit_order: order totals must be non-negative integers (minor units)' using errcode = '42501';
  end if;

  -- (authority: discounts — HARDENING-FIX-073) V1 kiosk has NO customer
  -- discount authority: a customer terminal can never price its own reduction.
  -- Both the order-level total AND every per-line discount must be exactly
  -- zero. Staff POS discounts (role-gated RPCs) are untouched.
  if p_client_discount_total_minor <> 0
     or exists (
       select 1 from jsonb_array_elements(p_order_items) e
         where (e ? 'line_discount_minor')
           and jsonb_typeof(e -> 'line_discount_minor') <> 'null'
           and app.order_parse_minor(e -> 'line_discount_minor', 'order_items[].line_discount_minor') <> 0) then
    v_result := jsonb_build_object('ok', false, 'error', 'discount_not_allowed', 'entity', 'order');
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'discount_not_allowed', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- (authority: currency — HARDENING-FIX-073) a syntactically valid ISO code is
  -- not enough for an untrusted terminal: the order currency must BE the tenant
  -- currency (the same coalesce(restaurants.currency_override,
  -- organizations.default_currency) kiosk_menu serves).
  select coalesce(r.currency_override, o.default_currency)
    into v_canon_currency
    from public.restaurants r
    join public.organizations o on o.id = r.organization_id
    where r.id = v_rest and r.organization_id = v_org;
  if v_canon_currency is null or p_currency_code <> v_canon_currency then
    v_result := jsonb_build_object('ok', false, 'error', 'currency_mismatch', 'entity', 'order',
                                   'expected_currency', v_canon_currency);
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'currency_mismatch', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- (payload+) order-type table SHAPE rules — submit_order VERBATIM.
  if p_order_type = 'takeaway' and p_table_id is not null then
    v_result := jsonb_build_object('ok', false, 'error', 'table_not_allowed', 'entity', 'order');
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'table_not_allowed', updated_at = now() where id = v_so_id;
    return v_result;
  end if;
  if p_order_type = 'dine_in' and p_table_id is null then
    v_result := jsonb_build_object('ok', false, 'error', 'table_required', 'entity', 'order');
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'table_required', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- (money recompute) from the SUBMITTED SNAPSHOTS ONLY — submit_order VERBATIM.
  for v_item in select * from jsonb_array_elements(p_order_items)
  loop
    v_qty       := app.order_parse_minor(v_item -> 'quantity', 'order_items[].quantity');
    if v_qty <= 0 or v_qty > 2147483647 then
      raise exception 'kiosk_submit_order: order_items[].quantity must be between 1 and 2147483647' using errcode = '42501';
    end if;
    v_unit      := app.order_parse_minor(v_item -> 'unit_price_minor_snapshot', 'order_items[].unit_price_minor_snapshot');
    v_line_disc := case when (v_item ? 'line_discount_minor') and jsonb_typeof(v_item -> 'line_discount_minor') <> 'null'
                        then app.order_parse_minor(v_item -> 'line_discount_minor', 'order_items[].line_discount_minor')
                        else 0 end;
    if (v_item ->> 'menu_item_id') is null then
      raise exception 'kiosk_submit_order: order_items[].menu_item_id is required' using errcode = '42501';
    end if;
    if (v_item ->> 'menu_item_name_snapshot') is null then
      raise exception 'kiosk_submit_order: order_items[].menu_item_name_snapshot is required' using errcode = '42501';
    end if;

    v_mod_sum := 0;
    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        if v_mod_qty <= 0 or v_mod_qty > 2147483647 then
          raise exception 'kiosk_submit_order: modifiers[].quantity must be between 1 and 2147483647' using errcode = '42501';
        end if;
        v_mod_sum := v_mod_sum + v_mod_price * v_mod_qty;
      end loop;
    end if;

    v_line_total := v_qty * (v_unit + v_mod_sum) - v_line_disc;
    if v_line_total < 0 then
      raise exception 'kiosk_submit_order: computed line_total_minor is negative' using errcode = '42501';
    end if;
    v_subtotal := v_subtotal + v_line_total;
  end loop;

  if p_client_subtotal_minor <> v_subtotal then
    raise exception 'kiosk_submit_order: client subtotal_minor (%) does not match snapshot recompute (%)',
      p_client_subtotal_minor, v_subtotal using errcode = '42501';
  end if;
  -- (authority: tax — HARDENING-FIX-073) the customer terminal never prices its
  -- own tax. The RF-117 per-branch owner setting is the single authority:
  -- disabled/0-bp => tax MUST be 0; enabled => tax MUST equal the canonical
  -- integer computation — round-HALF-AWAY-FROM-ZERO on a numeric transient,
  -- byte-matching the POS tax_math (`percentMinor`) and the money engine:
  --   exclusive: round(base * rate_bp / 10000)          (added on top)
  --   inclusive: round(base * rate_bp / (10000+rate_bp)) (extracted, not added)
  -- The base is the post-discount goods total, which for a kiosk (discounts
  -- forced 0 above) is the recomputed subtotal. A mismatch is the stable
  -- refresh-required refusal (the owner may have changed the rate mid-cart).
  select b.tax_enabled, b.tax_rate_bp, b.tax_mode
    into v_tax_enabled, v_tax_rate_bp, v_tax_mode
    from public.branches b
    where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;
  if not found then
    raise exception 'kiosk_submit_order: branch row unavailable during the tax gate (state inconsistency)';
  end if;
  if coalesce(v_tax_enabled, false) and coalesce(v_tax_rate_bp, 0) > 0 then
    if v_tax_mode = 'inclusive' then
      v_expected_tax := round((v_subtotal::numeric * v_tax_rate_bp) / (10000 + v_tax_rate_bp))::bigint;
    else
      v_expected_tax := round((v_subtotal::numeric * v_tax_rate_bp) / 10000)::bigint;
    end if;
  else
    v_expected_tax := 0;
  end if;
  if p_client_tax_total_minor <> v_expected_tax then
    v_result := jsonb_build_object('ok', false, 'error', 'tax_mismatch', 'entity', 'order',
                                   'expected_tax_total_minor', v_expected_tax);
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'tax_mismatch', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- discount proven 0 and tax proven canonical, so the grand total is fully
  -- server-derived: subtotal plus the tax only when the mode ADDS it.
  v_grand := v_subtotal
           + case when coalesce(v_tax_enabled, false) and coalesce(v_tax_rate_bp, 0) > 0
                       and v_tax_mode = 'exclusive'
                  then v_expected_tax else 0 end;
  if p_client_grand_total_minor <> v_grand then
    raise exception 'kiosk_submit_order: client grand_total_minor (%) does not match snapshot recompute (%)',
      p_client_grand_total_minor, v_grand using errcode = '42501';
  end if;

  -- (business replay backstop) orders UNIQUE (device_id, local_operation_id) —
  -- submit_order VERBATIM (belt under the ledger; also finalizes an adopted
  -- ledger row whose order actually committed).
  select o.id, o.revision, o.status into v_existing_id, v_existing_rev, v_existing_status
    from public.orders o
    where o.organization_id = v_org
      and o.device_id = p_device_id
      and o.local_operation_id = btrim(p_local_operation_id)
    limit 1;
  if found then
    v_result := jsonb_build_object(
      'ok', true, 'order_id', v_existing_id, 'revision', v_existing_rev,
      'server_ts', now(), 'idempotency_replay', true,
      'auto_completed', (v_existing_status = 'completed'),
      'order_status', v_existing_status);
    update public.sync_operations set status = 'applied', result = v_result,
      applied_at = coalesce(applied_at, now()), updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- (accept-1 KIOSK) owner decision B — the ATOMIC no-hold table gate.
  -- The chosen table must be a LIVE, ACTIVE, IN-SERVICE table of the SESSION
  -- branch (structural refusal identical to POS: 'table_not_available' — no
  -- existence oracle), and — KIOSK-ONLY — effectively AVAILABLE under a row
  -- lock: the row is locked FOR UPDATE, then manual state + DERIVED occupancy
  -- are evaluated under that lock. Two concurrent kiosk submits serialize on
  -- the lock; the loser sees the winner's committed dine-in order and gets the
  -- stable 'table_no_longer_available' refusal. POS submits are untouched:
  -- they never lock the table row and keep seating occupied/reserved tables
  -- (merging parties stays a staff power).
  if p_order_type = 'dine_in' then
    select t.status into v_t_status
      from public.tables t
      where t.id              = p_table_id
        and t.organization_id = v_org
        and t.restaurant_id   = v_rest
        and t.branch_id       = v_branch
        and t.is_active
        and t.deleted_at is null
      for update;
    if not found or v_t_status = 'out_of_service' then
      v_result := jsonb_build_object('ok', false, 'error', 'table_not_available', 'entity', 'order');
      update public.sync_operations set status = 'rejected', result = v_result,
        rejection_reason = 'table_not_available', updated_at = now() where id = v_so_id;
      return v_result;
    end if;
    if v_t_status in ('occupied', 'reserved')
       or exists (
         select 1 from public.orders o
           where o.organization_id = v_org
             and o.branch_id       = v_branch
             and o.order_type      = 'dine_in'
             and o.table_id        = p_table_id
             and o.deleted_at is null
             and o.status in ('submitted', 'accepted', 'preparing', 'ready', 'served')) then
      v_result := jsonb_build_object('ok', false, 'error', 'table_no_longer_available', 'entity', 'order');
      update public.sync_operations set status = 'rejected', result = v_result,
        rejection_reason = 'table_no_longer_available', updated_at = now() where id = v_so_id;
      return v_result;
    end if;
  end if;

  -- (accept-2) sellability + availability under the canonical menu_items
  -- FOR UPDATE serialization — submit_order VERBATIM.
  select array_agg(distinct (e ->> 'menu_item_id')::uuid)
    into v_item_ids
    from jsonb_array_elements(p_order_items) e;
  perform 1
    from public.menu_items i
    where i.organization_id = v_org
      and i.id = any (v_item_ids)
    order by i.id
    for update;

  select jsonb_agg(jsonb_build_object(
           'menu_item_id', blocked.menu_item_id,
           'name',         blocked.name,
           'reason',       blocked.reason)
           order by blocked.menu_item_id)
    into v_unavailable
    from (
      select li.menu_item_id,
             li.name,
             coalesce(a.reason, 'unavailable') as reason
        from (
          select (e ->> 'menu_item_id')::uuid as menu_item_id,
                 min(e ->> 'menu_item_name_snapshot') as name
            from jsonb_array_elements(p_order_items) e
            group by 1
        ) li
        left join public.menu_items i
          on i.id = li.menu_item_id
         and i.organization_id = v_org
         and i.restaurant_id   = v_rest
         and i.is_active
         and i.deleted_at is null
         and (i.branch_id is null or i.branch_id = v_branch)
        left join public.menu_categories c
          on c.id = i.menu_category_id
         and c.organization_id = v_org
         and c.restaurant_id   = v_rest
         and c.is_active
         and c.deleted_at is null
         and (c.branch_id is null or c.branch_id = v_branch)
        left join public.menu_item_branch_availability a
          on a.organization_id = v_org
         and a.branch_id       = v_branch
         and a.menu_item_id    = li.menu_item_id
         and a.availability    = 'unavailable'
        where i.id is null
           or c.id is null
           or a.menu_item_id is not null
    ) blocked;
  if v_unavailable is not null then
    v_result := jsonb_build_object('ok', false, 'error', 'item_unavailable',
                                   'entity', 'order', 'items', v_unavailable);
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'item_unavailable', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- (authority: item price — HARDENING-FIX-073) the kiosk client is untrusted:
  -- its submitted unit price snapshot must EQUAL the canonical live
  -- base_price_minor, read under the SAME menu_items FOR UPDATE serialization
  -- as the sellability gate (a concurrent price edit serializes against this
  -- submit). A mismatch is the stable refresh-required refusal — the server
  -- never silently charges a different amount than the cart showed.
  select jsonb_agg(jsonb_build_object(
           'menu_item_id', bad.menu_item_id, 'name', bad.name)
           order by bad.menu_item_id)
    into v_price_mismatch
    from (
      select distinct e ->> 'menu_item_id' as menu_item_id, i.name
        from jsonb_array_elements(p_order_items) e
        join public.menu_items i
          on i.id = (e ->> 'menu_item_id')::uuid
         and i.organization_id = v_org
       where (e ->> 'unit_price_minor_snapshot')::bigint is distinct from i.base_price_minor
    ) bad;
  if v_price_mismatch is not null then
    v_result := jsonb_build_object('ok', false, 'error', 'menu_price_changed',
                                   'entity', 'order', 'items', v_price_mismatch);
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'menu_price_changed', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- (003D) modifier option IDENTITY + OWNERSHIP — submit_order VERBATIM.
  select jsonb_agg(bad order by bad ->> 'menu_item_id', bad ->> 'option_name_snapshot')
    into v_bad_modifiers
    from (
      select distinct jsonb_build_object(
               'menu_item_id',        e ->> 'menu_item_id',
               'option_name_snapshot', m ->> 'option_name_snapshot') as bad
        from jsonb_array_elements(p_order_items) e
        cross join lateral jsonb_array_elements(
          case when jsonb_typeof(e -> 'modifiers') = 'array'
               then e -> 'modifiers' else '[]'::jsonb end) m
       where (m ->> 'modifier_option_id') is not null
         and not exists (
           select 1
             from public.modifier_options mo
             join public.modifiers mg
               on  mg.organization_id = mo.organization_id
               and mg.id              = mo.modifier_id
            where mo.organization_id = v_org
              and mo.id              = (m ->> 'modifier_option_id')::uuid
              and mg.menu_item_id    = (e ->> 'menu_item_id')::uuid
         )
    ) offenders;
  if v_bad_modifiers is not null then
    v_result := jsonb_build_object('ok', false, 'error', 'modifier_option_not_in_scope',
                                   'entity', 'order', 'modifiers', v_bad_modifiers);
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'modifier_option_not_in_scope', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- (authority: modifier liveness + price — HARDENING-FIX-073) ownership alone
  -- (003D above) is not enough for an untrusted terminal. Every selected option
  -- must be LIVE and branch-visible inside a LIVE branch-visible group (the
  -- exact kiosk_menu predicates), and its submitted price snapshot must EQUAL
  -- the canonical price_delta_minor. Dead/hidden selections are the stable
  -- selection refusal; a price drift is the stable refresh-required refusal.
  select jsonb_agg(bad order by bad ->> 'menu_item_id', bad ->> 'modifier_option_id')
    into v_invalid_mods
    from (
      select distinct jsonb_build_object(
               'menu_item_id',        e ->> 'menu_item_id',
               'modifier_option_id',  m ->> 'modifier_option_id',
               'reason',              'not_live') as bad
        from jsonb_array_elements(p_order_items) e
        cross join lateral jsonb_array_elements(
          case when jsonb_typeof(e -> 'modifiers') = 'array'
               then e -> 'modifiers' else '[]'::jsonb end) m
       where (m ->> 'modifier_option_id') is not null
         and not exists (
           select 1
             from public.modifier_options mo
             join public.modifiers mg
               on  mg.organization_id = mo.organization_id
               and mg.id              = mo.modifier_id
            where mo.organization_id = v_org
              and mo.restaurant_id   = v_rest
              and mo.id              = (m ->> 'modifier_option_id')::uuid
              and mo.is_active and mo.deleted_at is null
              and (mo.branch_id is null or mo.branch_id = v_branch)
              and mg.restaurant_id = v_rest
              and mg.is_active and mg.deleted_at is null
              and (mg.branch_id is null or mg.branch_id = v_branch)
         )
    ) offenders;
  if v_invalid_mods is not null then
    v_result := jsonb_build_object('ok', false, 'error', 'modifier_selection_invalid',
                                   'entity', 'order', 'modifiers', v_invalid_mods);
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'modifier_selection_invalid', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  select jsonb_agg(bad order by bad ->> 'menu_item_id', bad ->> 'modifier_option_id')
    into v_price_mismatch
    from (
      select distinct jsonb_build_object(
               'menu_item_id',       e ->> 'menu_item_id',
               'modifier_option_id', m ->> 'modifier_option_id') as bad
        from jsonb_array_elements(p_order_items) e
        cross join lateral jsonb_array_elements(
          case when jsonb_typeof(e -> 'modifiers') = 'array'
               then e -> 'modifiers' else '[]'::jsonb end) m
        join public.modifier_options mo
          on mo.organization_id = v_org
         and mo.id = (m ->> 'modifier_option_id')::uuid
       where (m ->> 'modifier_option_id') is not null
         and (m ->> 'price_minor_snapshot')::bigint is distinct from mo.price_delta_minor
    ) offenders;
  if v_price_mismatch is not null then
    v_result := jsonb_build_object('ok', false, 'error', 'menu_price_changed',
                                   'entity', 'order', 'modifiers', v_price_mismatch);
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'menu_price_changed', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- (authority: modifier group RULES — HARDENING-FIX-073) the server enforces
  -- the CURRENT group contract per submitted LINE, mirroring the POS sheet's
  -- effective rules exactly:
  --   effective_min = single ? 1 : (is_required and min_select=0 ? 1 : min_select)
  --   effective_max = single ? 1 : max_select   (null = unlimited)
  -- over DISTINCT selected options, and per-option TOTAL quantity (duplicate
  -- rows are SUMMED so they can never bypass a cap) = 1 unless the group
  -- allows quantities, else capped by max_quantity (null = no cap). The group
  -- universe is the item's LIVE branch-visible groups — a dead or hidden group
  -- is never demanded and never counted.
  with lines as (
    select t.ord, t.e
      from jsonb_array_elements(p_order_items) with ordinality t(e, ord)
  ),
  sel as (
    select l.ord,
           (l.e ->> 'menu_item_id')::uuid as item_id,
           (m ->> 'modifier_option_id')::uuid as option_id,
           sum(case when (m ? 'quantity') and jsonb_typeof(m -> 'quantity') <> 'null'
                    then (m ->> 'quantity')::bigint else 1 end) as total_qty
      from lines l
      cross join lateral jsonb_array_elements(
        case when jsonb_typeof(l.e -> 'modifiers') = 'array'
             then l.e -> 'modifiers' else '[]'::jsonb end) m
     where (m ->> 'modifier_option_id') is not null
     group by 1, 2, 3
  ),
  live_groups as (
    select mg.menu_item_id as item_id, mg.id as group_id, mg.name,
           mg.selection_type, mg.min_select, mg.max_select, mg.is_required,
           mg.allow_quantity, mg.max_quantity,
           case when mg.selection_type = 'single' then 1
                when mg.is_required and mg.min_select = 0 then 1
                else mg.min_select end as effective_min,
           case when mg.selection_type = 'single' then 1
                else mg.max_select end as effective_max
      from public.modifiers mg
      where mg.organization_id = v_org
        and mg.restaurant_id   = v_rest
        and mg.menu_item_id in (select distinct (e ->> 'menu_item_id')::uuid
                                  from jsonb_array_elements(p_order_items) e)
        and mg.is_active and mg.deleted_at is null
        and (mg.branch_id is null or mg.branch_id = v_branch)
  ),
  counts as (
    select s.ord, g.group_id,
           count(distinct s.option_id) as n_opts
      from sel s
      join public.modifier_options mo
        on mo.organization_id = v_org and mo.id = s.option_id
      join live_groups g
        on g.group_id = mo.modifier_id and g.item_id = s.item_id
      group by 1, 2
  ),
  violations as (
    -- (a) cardinality per line x live group (missing required group included:
    --     the cross join covers groups with NO selection at n = 0).
    select l.ord, g.group_id, g.name, 'selection_count'::text as kind
      from lines l
      join live_groups g on g.item_id = (l.e ->> 'menu_item_id')::uuid
      left join counts c on c.ord = l.ord and c.group_id = g.group_id
      where coalesce(c.n_opts, 0) < g.effective_min
         or (g.effective_max is not null and coalesce(c.n_opts, 0) > g.effective_max)
    union all
    -- (b) per-option quantity: exactly 1 unless quantities are allowed;
    --     otherwise capped by max_quantity (null = no cap).
    select s.ord, g.group_id, g.name, 'quantity'::text as kind
      from sel s
      join public.modifier_options mo
        on mo.organization_id = v_org and mo.id = s.option_id
      join live_groups g
        on g.group_id = mo.modifier_id and g.item_id = s.item_id
      where (not g.allow_quantity and s.total_qty <> 1)
         or (g.allow_quantity and g.max_quantity is not null and s.total_qty > g.max_quantity)
  )
  select jsonb_agg(distinct jsonb_build_object(
           'line', v.ord, 'modifier_id', v.group_id, 'modifier_name', v.name, 'kind', v.kind))
    into v_invalid_mods
    from violations v;
  if v_invalid_mods is not null then
    v_result := jsonb_build_object('ok', false, 'error', 'modifier_selection_invalid',
                                   'entity', 'order', 'modifiers', v_invalid_mods);
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'modifier_selection_invalid', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- (021) the frozen preparation snapshot must still match — submit_order VERBATIM.
  select jsonb_agg(bad order by bad ->> 'menu_item_id', bad ->> 'option_name_snapshot')
    into v_stale_modifiers
    from (
      select distinct jsonb_build_object(
               'menu_item_id',         e ->> 'menu_item_id',
               'option_name_snapshot', m ->> 'option_name_snapshot') as bad
        from jsonb_array_elements(p_order_items) e
        cross join lateral jsonb_array_elements(
          case when jsonb_typeof(e -> 'modifiers') = 'array'
               then e -> 'modifiers' else '[]'::jsonb end) m
       where (m ->> 'modifier_option_id') is not null
         and app.kitchen_modifier_prep_projection(m -> 'meat_snapshot')
             is distinct from
             app.trusted_modifier_prep_snapshot(
               v_org,
               (e ->> 'menu_item_id')::uuid,
               (m ->> 'modifier_option_id')::uuid,
               e -> 'modifiers')
    ) offenders;
  if v_stale_modifiers is not null then
    v_result := jsonb_build_object('ok', false, 'error', 'modifier_prep_snapshot_stale',
                                   'entity', 'order', 'modifiers', v_stale_modifiers);
    update public.sync_operations set status = 'rejected', result = v_result,
      rejection_reason = 'modifier_prep_snapshot_stale', updated_at = now() where id = v_so_id;
    return v_result;
  end if;

  -- (insert) order header at 'submitted' — the STAFF ACTOR TRIPLE IS NULL
  -- (owner decision A: the kiosk device is the actor); shift is NULL (kiosks
  -- have no cash shifts); customer name/phone are stamped in the same insert.
  insert into public.orders (
    id, organization_id, restaurant_id, branch_id, device_id, pin_session_id,
    opened_by_employee_profile_id, resolved_membership_id, table_id, shift_id,
    order_type, status, currency_code,
    subtotal_minor, discount_total_minor, tax_total_minor, grand_total_minor,
    notes, local_operation_id, revision, client_created_at,
    customer_name, customer_phone)
  values (
    p_order_id, v_org, v_rest, v_branch, p_device_id, null,
    null, null, p_table_id, null,
    p_order_type, 'submitted', p_currency_code,
    v_subtotal, p_client_discount_total_minor, p_client_tax_total_minor, v_grand,
    p_notes, btrim(p_local_operation_id), 1, p_client_created_at,
    nullif(v_customer_name, ''), nullif(v_customer_phone, ''));

  -- (insert) items + modifiers — submit_order VERBATIM.
  for v_item in select * from jsonb_array_elements(p_order_items)
  loop
    v_qty       := app.order_parse_minor(v_item -> 'quantity', 'order_items[].quantity');
    v_unit      := app.order_parse_minor(v_item -> 'unit_price_minor_snapshot', 'order_items[].unit_price_minor_snapshot');
    v_line_disc := case when (v_item ? 'line_discount_minor') and jsonb_typeof(v_item -> 'line_discount_minor') <> 'null'
                        then app.order_parse_minor(v_item -> 'line_discount_minor', 'order_items[].line_discount_minor')
                        else 0 end;
    v_mod_sum := 0;
    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        v_mod_sum := v_mod_sum + v_mod_price * v_mod_qty;
      end loop;
    end if;
    v_line_total := v_qty * (v_unit + v_mod_sum) - v_line_disc;

    -- (authority: canonical snapshots — HARDENING-FIX-073) the persisted
    -- receipt/kitchen snapshot is the CANONICAL validated menu row, never a
    -- client string (the client's copy stays in the request payload for wire
    -- compatibility and idempotency identity only). Kiosks sell no
    -- sizes/variants, so those legacy snapshot slots persist NULL.
    select i.name into v_canon_item_name
      from public.menu_items i
      where i.organization_id = v_org and i.id = (v_item ->> 'menu_item_id')::uuid;
    insert into public.order_items (
      organization_id, restaurant_id, branch_id, order_id, menu_item_id,
      status, quantity, menu_item_name_snapshot, unit_price_minor_snapshot,
      item_size_snapshot, item_variant_snapshot, line_discount_minor, line_total_minor, notes, prep_snapshot)
    values (
      v_org, v_rest, v_branch, p_order_id, (v_item ->> 'menu_item_id')::uuid,
      'pending', v_qty::int, v_canon_item_name, v_unit,
      null, null, v_line_disc, v_line_total,
      v_item ->> 'notes', v_item -> 'prep_snapshot')
    returning id into v_item_id;

    if (v_item ? 'modifiers') and jsonb_typeof(v_item -> 'modifiers') = 'array' then
      for v_modifier in select * from jsonb_array_elements(v_item -> 'modifiers')
      loop
        if (v_modifier ->> 'modifier_option_id') is null then
          raise exception 'kiosk_submit_order: modifiers[].modifier_option_id is required' using errcode = '42501';
        end if;
        if (v_modifier ->> 'option_name_snapshot') is null then
          raise exception 'kiosk_submit_order: modifiers[].option_name_snapshot is required' using errcode = '42501';
        end if;
        v_mod_price := app.order_parse_minor(v_modifier -> 'price_minor_snapshot', 'modifiers[].price_minor_snapshot');
        v_mod_qty   := case when (v_modifier ? 'quantity') and jsonb_typeof(v_modifier -> 'quantity') <> 'null'
                            then app.order_parse_minor(v_modifier -> 'quantity', 'modifiers[].quantity')
                            else 1 end;
        -- canonical group/option names + the canonical validated delta
        -- (HARDENING-FIX-073; the client strings were required above for wire
        -- shape but are never persisted).
        select mo.name, mg.name, mo.price_delta_minor
          into v_canon_opt_name, v_canon_mod_name, v_canon_delta
          from public.modifier_options mo
          join public.modifiers mg
            on mg.organization_id = mo.organization_id and mg.id = mo.modifier_id
          where mo.organization_id = v_org
            and mo.id = (v_modifier ->> 'modifier_option_id')::uuid;
        insert into public.order_item_modifiers (
          organization_id, restaurant_id, branch_id, order_item_id, modifier_option_id,
          modifier_name_snapshot, option_name_snapshot, price_minor_snapshot, quantity, meat_snapshot)
        values (
          v_org, v_rest, v_branch, v_item_id, (v_modifier ->> 'modifier_option_id')::uuid,
          v_canon_mod_name, v_canon_opt_name, v_canon_delta, v_mod_qty::int,
          app.kitchen_modifier_prep_projection(v_modifier -> 'meat_snapshot'));
        v_mod_count := v_mod_count + 1;
      end loop;
    end if;
    v_item_count := v_item_count + 1;
  end loop;

  -- (audit) append-only, in the SAME transaction. The kiosk DEVICE is the
  -- audited actor (owner decision A): both human actor columns NULL, device_id
  -- present (valid under the widened audit_events_actor_present), the action
  -- kiosk-namespaced and actor_kind explicit.
  insert into public.audit_events (
    organization_id, restaurant_id, branch_id,
    actor_app_user_id, actor_employee_profile_id, device_id,
    action, reason, old_values, new_values)
  values (
    v_org, v_rest, v_branch,
    null, null, p_device_id,
    'kiosk.order.submitted', null, null,
    jsonb_build_object(
      'actor_kind',             'kiosk_device',
      'order_id',               p_order_id,
      'status',                 'submitted',
      'revision',               1,
      'currency_code',          p_currency_code,
      'subtotal_minor',         v_subtotal,
      'discount_total_minor',   p_client_discount_total_minor,
      'tax_total_minor',        p_client_tax_total_minor,
      'grand_total_minor',      v_grand,
      'device_id',              p_device_id,
      'local_operation_id',     btrim(p_local_operation_id),
      'order_type',             p_order_type,
      'table_id',               p_table_id,
      'item_count',             v_item_count,
      'modifier_count',         v_mod_count));

  -- (tail) KITCHEN-MODE — submit_order VERBATIM semantics: a printer_only
  -- branch gets its durable kitchen dispatch in the SAME transaction (actor
  -- args NULL: dispatch audit rows are device-attributed, valid under the
  -- widened constraint), and a zero-total printer-only order auto-completes.
  select b.kitchen_workflow_mode into v_kitchen_mode
    from public.branches b
    where b.id              = v_branch
      and b.organization_id = v_org
      and b.deleted_at is null;
  if v_kitchen_mode is null then
    raise exception 'kiosk_submit_order: branch row unavailable during the kitchen dispatch gate (state inconsistency)';
  end if;

  if v_kitchen_mode = 'printer_only' then
    perform app.create_kitchen_dispatch(
      v_org, v_rest, v_branch, p_order_id, null, 'initial_order',
      app.kitchen_dispatch_payload_initial(v_org, p_order_id),
      null, null, p_device_id);
  end if;

  if v_grand = 0 then
    if v_kitchen_mode = 'printer_only' then
      v_auto := app.try_auto_complete_order(
        v_org, v_rest, v_branch, p_order_id,
        'order_submitted',
        null,          -- no JWT actor
        null, null, null,  -- no staff actor on the kiosk path (decision A)
        p_device_id, btrim(p_local_operation_id));
    end if;
  end if;

  v_result := jsonb_build_object(
    'ok', true, 'order_id', p_order_id,
    'revision', coalesce((v_auto ->> 'revision')::integer, 1),
    'server_ts', now(), 'idempotency_replay', false,
    'auto_completed', coalesce((v_auto ->> 'completed')::boolean, false),
    'order_status', case when coalesce((v_auto ->> 'completed')::boolean, false)
                         then 'completed' else 'submitted' end);
  update public.sync_operations set status = 'applied', result = v_result,
    applied_at = now(), updated_at = now() where id = v_so_id;
  return v_result;
end;
$$;

comment on function app.kiosk_submit_order(uuid, text, uuid, text, text, uuid, text, text, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz) is
  'KIOSK-001 Phase 2: the ONE kiosk mutation — a customer order submit authorized by a kiosk device session token (device_type=kiosk; NO PIN session, NO staff permissions). Validation is app.submit_order''s, block for block (shape/currency/type, snapshot-only money recompute, canonical sellability + availability under the menu_items FOR UPDATE serialization, 003D modifier ownership, 021 frozen-prep comparison, KITCHEN-MODE dispatch + zero-total auto-complete tail). KIOSK deltas: (a) transport-ledger claim (sync_push b2 contract) for op kiosk.order.submit with the phone-excluded fingerprint + business replay backstop on orders (D-022); (b) owner decision B — the dine-in table row is LOCKED (FOR UPDATE) and must be effectively AVAILABLE (manual available + zero live dine-in orders); concurrent losers get the stable table_no_longer_available refusal; POS merge-parties semantics untouched; NO holds, NO new columns; (c) owner decision A — staff actor triple NULL, shift NULL, the kiosk device is the audited actor (kiosk.order.submitted, actor_kind=kiosk_device); (d) optional customer name/phone validated up front (app.is_valid_customer_phone) and stamped in the insert; phone is data-only and excluded from the idempotency fingerprint. The order is UNPAID (pay-at-cashier: record_payment/settlement/auto-completion unchanged) and enters the normal kitchen lifecycle/projections. HARDENING-FIX-073 — the kiosk client is UNTRUSTED: submitted item/option prices must EQUAL the canonical live base_price_minor / price_delta_minor under the same FOR UPDATE serialization (else the stable menu_price_changed refresh refusal — the server never silently reprices); modifier group rules (required/min/max/single/quantity, POS effective-rule parity, duplicates summed) are server-enforced (modifier_selection_invalid), selected options/groups must be LIVE and branch-visible; customer discounts are prohibited (discount_not_allowed, order and line level); the currency must BE the tenant currency (currency_mismatch); tax is server-computed from the RF-117 branch setting with round-half-away-from-zero (tax_mismatch); persisted item/group/option name snapshots are the CANONICAL menu rows, never client strings, and kiosk lines persist NULL size/variant slots.';

-- ----------------------------------------------------------------------------
-- 11. public wrappers + exact grants (the get_device_printer_assignments
--     convention: SECURITY INVOKER pass-through; authenticated only — the
--     anonymous device principal IS authenticated; never anon/service_role).
-- ----------------------------------------------------------------------------
create or replace function public.kiosk_menu(
  p_device_id uuid, p_session_token text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.kiosk_menu(p_device_id, p_session_token); $$;

create or replace function public.kiosk_tables(
  p_device_id uuid, p_session_token text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.kiosk_tables(p_device_id, p_session_token); $$;

create or replace function public.kiosk_submit_order(
  p_device_id uuid, p_session_token text, p_order_id uuid, p_local_operation_id text,
  p_order_type text, p_table_id uuid, p_currency_code text, p_notes text,
  p_customer_name text, p_customer_phone text, p_order_items jsonb,
  p_client_subtotal_minor bigint, p_client_discount_total_minor bigint,
  p_client_tax_total_minor bigint, p_client_grand_total_minor bigint,
  p_client_created_at timestamptz default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.kiosk_submit_order(p_device_id, p_session_token, p_order_id, p_local_operation_id,
  p_order_type, p_table_id, p_currency_code, p_notes, p_customer_name, p_customer_phone,
  p_order_items, p_client_subtotal_minor, p_client_discount_total_minor,
  p_client_tax_total_minor, p_client_grand_total_minor, p_client_created_at); $$;

revoke all on function app.kiosk_menu(uuid, text)    from public;
grant execute on function app.kiosk_menu(uuid, text) to authenticated;
revoke all on function public.kiosk_menu(uuid, text)    from public;
grant execute on function public.kiosk_menu(uuid, text) to authenticated;

revoke all on function app.kiosk_tables(uuid, text)    from public;
grant execute on function app.kiosk_tables(uuid, text) to authenticated;
revoke all on function public.kiosk_tables(uuid, text)    from public;
grant execute on function public.kiosk_tables(uuid, text) to authenticated;

revoke all on function app.kiosk_submit_order(uuid, text, uuid, text, text, uuid, text, text, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz)    from public;
grant execute on function app.kiosk_submit_order(uuid, text, uuid, text, text, uuid, text, text, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz) to authenticated;
revoke all on function public.kiosk_submit_order(uuid, text, uuid, text, text, uuid, text, text, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz)    from public;
grant execute on function public.kiosk_submit_order(uuid, text, uuid, text, text, uuid, text, text, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz) to authenticated;

comment on function public.kiosk_menu(uuid, text) is
  'KIOSK-001 Phase 2 pass-through wrapper for app.kiosk_menu (SECURITY INVOKER; security enforced inside app.* by the kiosk device token proof).';
comment on function public.kiosk_tables(uuid, text) is
  'KIOSK-001 Phase 2 pass-through wrapper for app.kiosk_tables (SECURITY INVOKER; security enforced inside app.* by the kiosk device token proof).';
comment on function public.kiosk_submit_order(uuid, text, uuid, text, text, uuid, text, text, text, text, jsonb, bigint, bigint, bigint, bigint, timestamptz) is
  'KIOSK-001 Phase 2 pass-through wrapper for app.kiosk_submit_order (SECURITY INVOKER; security enforced inside app.* by the kiosk device token proof).';
