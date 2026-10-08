-- ============================================================================
-- ORDER-EDIT-001A (1 of 3) — schema for editing a sent, open, unpaid order.
-- DECISION D-043 (an in-place delta edit of the SAME order) and D-044 (the
-- kitchen is told precisely). Contract: API_CONTRACT §4.45 / §4.46; entities:
-- DOMAIN_MODEL §2.3, §6.2, §6.4; design record: ORDER_EDIT_DESIGN §8.1.
--
-- SHIPS DARK. Every change below is ADDITIVE and backward compatible: new
-- nullable columns, new columns with defaults, a new table, widened CHECKs, a
-- new owner setter. Nothing is written by an edit until a branch's
-- order_edit_enabled switch is turned ON (default OFF), and the switch is the
-- rollout gate (§4.45.8: update every KDS, then every POS, then turn it on).
--
-- WHAT THIS MIGRATION ADDS / CHANGES
--   1. public.order_edits                — new, money-free, append-only
--   2. order_items edit provenance       — edit_id, removed_by_edit_id,
--      replaces_order_item_id, removed_kitchen_stage (+ UNIQUE (org, order, id),
--      composite FKs, CHECKs and a write-once guard trigger)
--   3. order_service_rounds              — edit_id, voided_by_edit_id
--   4. orders.edit_count
--   5. order_operations action CHECK     — + 'edit_order' (the stored
--      success envelope of app.edit_order is replayed from this ledger)
--   6. branches switches                 — order_edit_enabled,
--      order_edit_finished_food_manager_only (both default false)
--   7. app.set_branch_order_edit_settings + its SECURITY INVOKER public
--      wrapper (D-037: PUBLIC and anon revoked explicitly on both)
--   8. kitchen_print_dispatches          — dispatch_type += 'order_edit',
--      order_edit_id (+ CHECK + composite FK), and the amended supersession
--      guard (write-once pointer; target void or order_edit; a void is never
--      superseded) — replaces the CORRECTION-001 "chain length exactly 1" rule
--   9. sync_operations.operation_type CHECK += 'order.edit', 'order.edit_ack'
--
-- NO money column is added anywhere (D-007 scope); order_edits, service
-- rounds and kitchen payloads carry no money (T-003).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. public.order_edits — one row per APPLIED sent-order edit (D-043).
--    A refused edit writes no row (refusals are audited order.edit_denied).
-- ----------------------------------------------------------------------------
create table public.order_edits (
  id                                 uuid        not null default gen_random_uuid(),
  organization_id                    uuid        not null references public.organizations (id) on delete restrict,
  restaurant_id                      uuid        not null,
  branch_id                          uuid        not null,
  order_id                           uuid        not null,
  -- 1, 2, 3 … per order, allocated as orders.edit_count + 1 under the order lock.
  edit_number                        integer     not null check (edit_number >= 1),
  -- the acting POS + its operation id: the BUSINESS replay key (D-022).
  device_id                          uuid        not null,
  local_operation_id                 text        not null check (length(btrim(local_operation_id)) > 0),
  pin_session_id                     uuid        not null,
  employee_profile_id                uuid        not null,
  membership_id                      uuid        not null,
  reason_code                        text
    check (reason_code is null
           or reason_code in ('customer_changed_mind', 'entry_mistake', 'item_unavailable', 'kitchen_issue', 'other')),
  reason_text                        text
    check (reason_text is null or (char_length(reason_text) between 1 and 200)),
  -- paper iff the branch is printer_only at commit (a direct_print order on a
  -- branch that has since switched to KDS is refused, kitchen_mode_changed).
  kitchen_channel                    text        not null check (kitchen_channel in ('kds', 'paper')),
  kitchen_ack_required               boolean     not null default false,
  -- the kitchen's one-time "Got it" (D-044; app.kitchen_ack_order_edit).
  kitchen_ack_at                     timestamptz,
  kitchen_ack_by_employee_profile_id uuid,
  kitchen_ack_device_id              uuid,
  bill_presented_at                  timestamptz,
  client_created_at                  timestamptz,
  created_at                         timestamptz not null default now(),
  updated_at                         timestamptz not null default now(),
  deleted_at                         timestamptz,
  primary key (id),
  unique (organization_id, id),
  -- the composite same-ORDER FK target for order_items / rounds / dispatches.
  unique (organization_id, order_id, id),
  unique (organization_id, order_id, edit_number),
  unique (organization_id, device_id, local_operation_id),
  -- the acknowledgement triple: all-or-none, only when required, never on paper.
  constraint order_edits_kitchen_ack_state_check
    check (((kitchen_ack_at is null) = (kitchen_ack_by_employee_profile_id is null))
           and ((kitchen_ack_at is null) = (kitchen_ack_device_id is null))
           and (kitchen_ack_at is null or kitchen_ack_required)),
  constraint order_edits_paper_no_ack_check
    check (kitchen_channel = 'kds' or not kitchen_ack_required),
  constraint order_edits_reason_other_text_check
    check (reason_code is distinct from 'other' or reason_text is not null),
  foreign key (organization_id, restaurant_id, branch_id)
    references public.branches (organization_id, restaurant_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id, order_id)
    references public.orders (organization_id, restaurant_id, branch_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id, device_id)
    references public.devices (organization_id, restaurant_id, branch_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id, pin_session_id)
    references public.pin_sessions (organization_id, restaurant_id, branch_id, id) on delete restrict,
  foreign key (organization_id, employee_profile_id)
    references public.employee_profiles (organization_id, id) on delete restrict,
  foreign key (organization_id, membership_id)
    references public.memberships (organization_id, id) on delete restrict,
  constraint order_edits_kitchen_ack_employee_fkey
    foreign key (organization_id, kitchen_ack_by_employee_profile_id)
    references public.employee_profiles (organization_id, id) on delete restrict,
  constraint order_edits_kitchen_ack_device_fkey
    foreign key (organization_id, restaurant_id, branch_id, kitchen_ack_device_id)
    references public.devices (organization_id, restaurant_id, branch_id, id) on delete restrict
);

comment on table public.order_edits is
  'ORDER-EDIT-001A (D-043/D-044): one APPEND-ONLY, MONEY-FREE row per applied sent-order edit — an in-place delta edit of the SAME open, unpaid order. Written ONLY by app.edit_order (sync op order.edit, insert) and app.kitchen_ack_order_edit (sync op order.edit_ack, the one-time acknowledgement stamp). edit_number is unique per order (orders.edit_count + 1 under the order lock); (organization_id, device_id, local_operation_id) is the business replay key (D-022). No status column, no new state (D-018 unchanged). After insert only the acknowledgement triple (once) and updated_at may change; deletes are refused. The money effect lives on orders / order_items (MONEY_AND_TAX_SPEC §9.2) and the per-line record in the order.edited audit event.';

create index order_edits_order_idx  on public.order_edits (organization_id, order_id);
create index order_edits_branch_idx on public.order_edits (organization_id, restaurant_id, branch_id);
create index order_edits_pending_ack_idx
  on public.order_edits (organization_id, order_id)
  where kitchen_ack_required and kitchen_ack_at is null;

-- APPEND-ONLY guard: after insert only the one-time acknowledgement stamp and
-- updated_at may change, and a row can never be deleted.
create or replace function app.order_edits_guard()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'order_edits: rows are append-only and can never be deleted'
      using errcode = '23514';
  end if;
  if (to_jsonb(new) - 'kitchen_ack_at' - 'kitchen_ack_by_employee_profile_id'
                    - 'kitchen_ack_device_id' - 'updated_at')
     is distinct from
     (to_jsonb(old) - 'kitchen_ack_at' - 'kitchen_ack_by_employee_profile_id'
                    - 'kitchen_ack_device_id' - 'updated_at') then
    raise exception 'order_edits: only the one-time kitchen acknowledgement may change after insert'
      using errcode = '23514';
  end if;
  if old.kitchen_ack_at is not null
     and (new.kitchen_ack_at is distinct from old.kitchen_ack_at
          or new.kitchen_ack_by_employee_profile_id is distinct from old.kitchen_ack_by_employee_profile_id
          or new.kitchen_ack_device_id is distinct from old.kitchen_ack_device_id) then
    raise exception 'order_edits: the kitchen acknowledgement is write-once'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

comment on function app.order_edits_guard() is
  'ORDER-EDIT-001A: BEFORE UPDATE/DELETE guard keeping public.order_edits append-only — only the one-time acknowledgement triple (NULL -> value, once) and updated_at may change; deletes raise 23514.';

revoke all on function app.order_edits_guard() from public;
revoke all on function app.order_edits_guard() from anon;
revoke all on function app.order_edits_guard() from authenticated;

create trigger order_edits_guard
  before update or delete on public.order_edits
  for each row execute function app.order_edits_guard();

create trigger order_edits_set_updated_at
  before update on public.order_edits
  for each row execute function app.set_updated_at();

alter table public.order_edits enable row level security;
alter table public.order_edits force  row level security;

-- SELECT scoped exactly like order_service_rounds (money-free, so has_scope —
-- the kitchen reads it for its change cards, ORDER-EDIT-001D); every write is
-- denied to clients (only the SECURITY DEFINER RPCs write, D-011).
create policy order_edits_sel on public.order_edits
  for select to authenticated
  using (organization_id = app.current_org_id()
         and app.has_scope(organization_id, restaurant_id, branch_id));
create policy order_edits_ins_deny on public.order_edits
  for insert to authenticated with check (false);
create policy order_edits_upd_deny on public.order_edits
  for update to authenticated using (false) with check (false);
create policy order_edits_del_deny on public.order_edits
  for delete to authenticated using (false);

revoke all privileges on table public.order_edits from public;
revoke all privileges on table public.order_edits from anon;
grant select on public.order_edits to authenticated;
revoke insert, update, delete on public.order_edits from authenticated;

-- ----------------------------------------------------------------------------
-- 2. order_items — edit PROVENANCE (not states; D-018 unchanged).
-- ----------------------------------------------------------------------------
alter table public.order_items
  add constraint order_items_org_order_id_key unique (organization_id, order_id, id);

alter table public.order_items
  add column edit_id                uuid,
  add column removed_by_edit_id     uuid,
  add column replaces_order_item_id uuid,
  add column removed_kitchen_stage  text;

alter table public.order_items add constraint order_items_removed_kitchen_stage_check
  check (removed_kitchen_stage is null
         or removed_kitchen_stage in ('submitted', 'accepted', 'preparing', 'ready', 'served', 'printed'));
alter table public.order_items add constraint order_items_removed_status_check
  check (removed_by_edit_id is null or status in ('voided', 'cancelled'));
alter table public.order_items add constraint order_items_removed_stage_pair_check
  check ((removed_by_edit_id is null) = (removed_kitchen_stage is null));
alter table public.order_items add constraint order_items_replaces_requires_edit_check
  check (replaces_order_item_id is null or edit_id is not null);

-- Composite same-ORDER FKs (MATCH SIMPLE: a NULL provenance column is exempt).
alter table public.order_items add constraint order_items_edit_fkey
  foreign key (organization_id, order_id, edit_id)
  references public.order_edits (organization_id, order_id, id) on delete restrict;
alter table public.order_items add constraint order_items_removed_by_edit_fkey
  foreign key (organization_id, order_id, removed_by_edit_id)
  references public.order_edits (organization_id, order_id, id) on delete restrict;
alter table public.order_items add constraint order_items_replaces_fkey
  foreign key (organization_id, order_id, replaces_order_item_id)
  references public.order_items (organization_id, order_id, id) on delete restrict;

comment on column public.order_items.edit_id is
  'ORDER-EDIT-001A (D-043): the order edit that WROTE this row (set on every row app.edit_order inserts; NULL on submit / add-items rows). Immutable after insert.';
comment on column public.order_items.removed_by_edit_id is
  'ORDER-EDIT-001A (D-043): the order edit that RETIRED this row (status cancelled/voided, void_reason order_edit:<reason>). Write-once. Edit-retired lines are reported in the Order edits bucket, never Voids (MONEY_AND_TAX_SPEC §13).';
comment on column public.order_items.replaces_order_item_id is
  'ORDER-EDIT-001A (D-043): set on a remainder / continuation / modify-replacement row = the retired line it replaces (same order, composite FK). Increase deltas and added lines carry none (MONEY M13 classifies on this). Immutable after insert.';
comment on column public.order_items.removed_kitchen_stage is
  'ORDER-EDIT-001A (D-043): PROVENANCE, NOT A STATE — the stage of the retired line''s work unit at commit (submitted|accepted|preparing|ready|served on the KDS channel; printed on the paper channel). Write-once, set together with removed_by_edit_id.';

-- Write-once guard on the four provenance columns: edit_id and
-- replaces_order_item_id are fixed at insert; removed_by_edit_id and
-- removed_kitchen_stage go NULL -> value exactly once.
create or replace function app.order_items_edit_provenance_guard()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  if new.edit_id is distinct from old.edit_id
     or new.replaces_order_item_id is distinct from old.replaces_order_item_id then
    raise exception 'order_items: edit_id / replaces_order_item_id are fixed at insert'
      using errcode = '23514';
  end if;
  if (old.removed_by_edit_id is not null
        and new.removed_by_edit_id is distinct from old.removed_by_edit_id)
     or (old.removed_kitchen_stage is not null
        and new.removed_kitchen_stage is distinct from old.removed_kitchen_stage) then
    raise exception 'order_items: removed_by_edit_id / removed_kitchen_stage are write-once'
      using errcode = '23514';
  end if;
  return new;
end;
$$;

comment on function app.order_items_edit_provenance_guard() is
  'ORDER-EDIT-001A: BEFORE UPDATE guard on order_items — edit_id and replaces_order_item_id never change after insert; removed_by_edit_id and removed_kitchen_stage are write-once (NULL -> value). Raises 23514.';

revoke all on function app.order_items_edit_provenance_guard() from public;
revoke all on function app.order_items_edit_provenance_guard() from anon;
revoke all on function app.order_items_edit_provenance_guard() from authenticated;

create trigger order_items_edit_provenance_guard
  before update on public.order_items
  for each row execute function app.order_items_edit_provenance_guard();

create index order_items_removed_by_edit_idx
  on public.order_items (organization_id, removed_by_edit_id)
  where removed_by_edit_id is not null;
create index order_items_edit_idx
  on public.order_items (organization_id, edit_id)
  where edit_id is not null;

-- ----------------------------------------------------------------------------
-- 3. order_service_rounds — the round an edit OPENED, and the round an edit
--    EMPTIED (voided while submitted..ready; ignored by order_rounds_all_served).
-- ----------------------------------------------------------------------------
alter table public.order_service_rounds
  add column edit_id           uuid,
  add column voided_by_edit_id uuid;

alter table public.order_service_rounds add constraint order_service_rounds_voided_by_edit_check
  check (voided_by_edit_id is null or status = 'voided');
alter table public.order_service_rounds add constraint order_service_rounds_edit_fkey
  foreign key (organization_id, order_id, edit_id)
  references public.order_edits (organization_id, order_id, id) on delete restrict;
alter table public.order_service_rounds add constraint order_service_rounds_voided_by_edit_fkey
  foreign key (organization_id, order_id, voided_by_edit_id)
  references public.order_edits (organization_id, order_id, id) on delete restrict;

comment on column public.order_service_rounds.edit_id is
  'ORDER-EDIT-001A (D-043): the order edit that opened this round (at most one per edit; numbered like any round, created submitted). NULL for add-items rounds.';
comment on column public.order_service_rounds.voided_by_edit_id is
  'ORDER-EDIT-001A (D-043): the order edit that EMPTIED this round while submitted..ready (CHECK => status voided). app.order_rounds_all_served ignores ONLY such rounds, so an edit-emptied round never blocks completion of a live order.';

-- ----------------------------------------------------------------------------
-- 4. orders.edit_count — how many edits were applied (edit_number allocator).
-- ----------------------------------------------------------------------------
alter table public.orders
  add column edit_count integer not null default 0
    constraint orders_edit_count_check check (edit_count >= 0);

comment on column public.orders.edit_count is
  'ORDER-EDIT-001A (D-043): number of applied sent-order edits; each app.edit_order bumps it (and revision) by one and allocates edit_number = edit_count + 1 under the order lock.';

-- ----------------------------------------------------------------------------
-- 5. order_operations — app.edit_order stores its success envelope here (the
--    envelope carries totals, so it does NOT live on the money-free
--    order_edits row); a business replay returns it verbatim (D-022).
-- ----------------------------------------------------------------------------
alter table public.order_operations drop constraint order_operations_action_check;
alter table public.order_operations add  constraint order_operations_action_check
  check (action in ('void_order', 'apply_discount', 'record_payment', 'move_table', 'edit_order'));

comment on constraint order_operations_action_check on public.order_operations is
  'RF-053/RF-054 + RESTAURANT-OPERATIONS-V1-001 + ORDER-EDIT-001A: business-idempotency actions — void_order / apply_discount / record_payment / move_table / edit_order.';

-- ----------------------------------------------------------------------------
-- 6. branches — the two owner switches (both default OFF: ships dark).
-- ----------------------------------------------------------------------------
alter table public.branches
  add column order_edit_enabled                    boolean not null default false,
  add column order_edit_finished_food_manager_only boolean not null default false;

comment on column public.branches.order_edit_enabled is
  'ORDER-EDIT-001A (D-043/D-044): "Allow editing sent orders". Default false. While false app.edit_order refuses with feature_disabled. The rollout gate: turn on only after every KDS, then every POS, of the branch runs an edit-aware build (API_CONTRACT §4.45.8). Written only by app.set_branch_order_edit_settings.';
comment on column public.branches.order_edit_finished_food_manager_only is
  'ORDER-EDIT-001A (D-043): "Only managers may remove food that is Ready or Served". Default false. Applies on the KDS channel only; on a printer-only branch it has no effect (no kitchen screen tells when food is ready) but the stored value is kept (Q-046). Written only by app.set_branch_order_edit_settings.';

-- ----------------------------------------------------------------------------
-- 7. app.set_branch_order_edit_settings — OWNER write of both switches (the
--    RF-113 template: rank >= restaurant_owner; per-actor idempotent ledger;
--    append-only audit). PUBLIC and anon revoked explicitly (D-037).
-- ----------------------------------------------------------------------------
create or replace function app.set_branch_order_edit_settings(
  p_client_request_id          uuid,
  p_organization_id            uuid,
  p_restaurant_id              uuid,
  p_branch_id                  uuid,
  p_order_edit_enabled         boolean,
  p_finished_food_manager_only boolean
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
    raise exception 'set_branch_order_edit_settings: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'set_branch_order_edit_settings: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    raise exception 'set_branch_order_edit_settings: organization_id, restaurant_id and branch_id are required' using errcode = '42501';
  end if;
  if p_order_edit_enabled is null or p_finished_food_manager_only is null then
    raise exception 'set_branch_order_edit_settings: both settings are required' using errcode = '42501';
  end if;

  -- the branch AND its parent restaurant must be LIVE (not soft-deleted), and
  -- the caller must hold a membership covering it. Both are decided BEFORE
  -- the idempotency lookup and fail with ONE message, so neither a missing
  -- branch, another tenant's real branch, nor a reused request key can tell
  -- them apart (no cross-tenant existence oracle, R-003).
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0
     or not exists (select 1 from public.branches b
                    join public.restaurants r
                      on r.id = b.restaurant_id and r.organization_id = b.organization_id
                    where b.id = p_branch_id and b.organization_id = p_organization_id
                      and b.restaurant_id = p_restaurant_id
                      and b.deleted_at is null and r.deleted_at is null) then
    raise exception 'set_branch_order_edit_settings: branch not found or not accessible' using errcode = '42501';
  end if;

  v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id,
              'branch', p_branch_id, 'order_edit_enabled', p_order_edit_enabled,
              'order_edit_finished_food_manager_only', p_finished_food_manager_only)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'set_branch_order_edit_settings', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  -- SAME rank gate as RF-112/113/117: rank >= restaurant_owner (3). A
  -- manager, cashier or kitchen member is DENIED (audited, no raise).
  if v_rank < 3 then
    perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id, 'settings.branch.update_denied', null,
      jsonb_build_object('branch_id', p_branch_id, 'setting', 'order_edit'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'branch');
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'branch',
                'branch_id', p_branch_id,
                'order_edit_enabled', p_order_edit_enabled,
                'order_edit_finished_food_manager_only', p_finished_food_manager_only);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'set_branch_order_edit_settings', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  select jsonb_build_object('branch_id', t.id,
                            'order_edit_enabled', t.order_edit_enabled,
                            'order_edit_finished_food_manager_only', t.order_edit_finished_food_manager_only)
    into v_old from public.branches t where t.id = p_branch_id;
  update public.branches
    set order_edit_enabled                    = p_order_edit_enabled,
        order_edit_finished_food_manager_only = p_finished_food_manager_only
    where id = p_branch_id;
  select jsonb_build_object('branch_id', t.id,
                            'order_edit_enabled', t.order_edit_enabled,
                            'order_edit_finished_food_manager_only', t.order_edit_finished_food_manager_only)
    into v_new from public.branches t where t.id = p_branch_id;
  perform app.management_audit(p_organization_id, p_restaurant_id, p_branch_id,
    'settings.branch.order_edit_updated', v_old, v_new);
  return v_result;
end;
$$;

comment on function app.set_branch_order_edit_settings(uuid, uuid, uuid, uuid, boolean, boolean) is
  'ORDER-EDIT-001A (D-043/D-044; API_CONTRACT §4.45.8): OWNER write of branches.order_edit_enabled + branches.order_edit_finished_food_manager_only. The RF-113 template: actor from auth (null => 42501); a live branch + restaurant AND a covering membership, both decided before the idempotency lookup with ONE 42501 message (no cross-tenant existence oracle); per-actor idempotent via p_client_request_id (management_request_results; same key + different input => 42501); rank >= restaurant_owner over the branch (manager/cashier/kitchen => settings.branch.update_denied audit + {ok:false, error:permission_denied}, no raise). Success writes ONE append-only settings.branch.order_edit_updated audit with old/new values of the two switches and returns {ok, idempotent_replay, entity:branch, branch_id, order_edit_enabled, order_edit_finished_food_manager_only}. Policy flags only (no money).';

create or replace function public.set_branch_order_edit_settings(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid,
  p_order_edit_enabled boolean, p_finished_food_manager_only boolean)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.set_branch_order_edit_settings(p_client_request_id, p_organization_id, p_restaurant_id, p_branch_id, p_order_edit_enabled, p_finished_food_manager_only); $$;

comment on function public.set_branch_order_edit_settings(uuid, uuid, uuid, uuid, boolean, boolean) is
  'ORDER-EDIT-001A: thin SECURITY INVOKER wrapper over app.set_branch_order_edit_settings (the Dashboard toggles are ORDER-EDIT-001G). authenticated only; PUBLIC and anon revoked (D-037).';

revoke all on function app.set_branch_order_edit_settings(uuid, uuid, uuid, uuid, boolean, boolean) from public;
revoke all on function app.set_branch_order_edit_settings(uuid, uuid, uuid, uuid, boolean, boolean) from anon;
grant execute on function app.set_branch_order_edit_settings(uuid, uuid, uuid, uuid, boolean, boolean) to authenticated;
revoke all on function public.set_branch_order_edit_settings(uuid, uuid, uuid, uuid, boolean, boolean) from public;
revoke all on function public.set_branch_order_edit_settings(uuid, uuid, uuid, uuid, boolean, boolean) from anon;
grant execute on function public.set_branch_order_edit_settings(uuid, uuid, uuid, uuid, boolean, boolean) to authenticated;

-- ----------------------------------------------------------------------------
-- 8. kitchen_print_dispatches — the order_edit dispatch type (paper channel).
-- ----------------------------------------------------------------------------
alter table public.kitchen_print_dispatches
  drop constraint kitchen_print_dispatches_dispatch_type_check;
alter table public.kitchen_print_dispatches
  add constraint kitchen_print_dispatches_dispatch_type_check
  check (dispatch_type in ('initial_order', 'service_round', 'void', 'order_edit'));

alter table public.kitchen_print_dispatches
  add column order_edit_id uuid;

alter table public.kitchen_print_dispatches
  add constraint kitchen_print_dispatches_order_edit_type
  check ((dispatch_type = 'order_edit') = (order_edit_id is not null));
-- an order_edit dispatch must reference an edit OF THAT ORDER (MATCH SIMPLE:
-- non-edit dispatches carry NULL and are exempt).
alter table public.kitchen_print_dispatches
  add constraint kitchen_print_dispatches_order_edit_fkey
  foreign key (organization_id, order_id, order_edit_id)
  references public.order_edits (organization_id, order_id, id) on delete restrict;

comment on column public.kitchen_print_dispatches.order_edit_id is
  'ORDER-EDIT-001A (D-044): the order edit an order_edit dispatch prints (key edit:<order_edit_id>); CHECK (dispatch_type = order_edit) = (order_edit_id is not null).';

comment on table public.kitchen_print_dispatches is
  'KITCHEN-MODE-001C1: the durable server ledger guaranteeing every ACCEPTED printer-only kitchen event (initial order / service-round delta / void / ORDER-EDIT-001A order edit) has an idempotent MONEY-FREE dispatch created IN THE SAME TRANSACTION as the acceptance. The POS pulls-and-claims atomically (10-min claim expiry; stale claims reclaimable), imports into its encrypted local spool (001C2), prints, and acknowledges. claimed/completed/last_client_status semantics ONLY — deliberately NO printed boolean (transport acceptance is never a paper claim). Dispatch state is INDEPENDENT of order state. CORRECTION-001 retention contract: an UNRESOLVED row NEVER ages out of any read surface (it stays pullable and stays a transition blocker regardless of age); completed rows are permanent history in this phase (any pruning/archival of COMPLETED rows is a later, separate decision — never of unresolved ones). Structural FKs tie order/branch, service round, order edit, claimed device and supersession to authoritative rows. ORDER-EDIT-001A: an order_edit dispatch (key edit:<order_edit_id>) is created already CLAIMED by the acting POS and supersedes the order''s unresolved initial / round / earlier edit dispatches; a later void supersedes it.';

-- The amended supersession guard (API_CONTRACT §4.45.9). The money-free key
-- scan and the 32KB cap are unchanged. The pointer is WRITE-ONCE; its target
-- must be a void or order_edit dispatch of the same org + order (composite FK
-- + no-self CHECK); "the target is itself unsuperseded" is checked ONLY when
-- the pointer is being set; a void row can never be superseded.
create or replace function app.kitchen_print_dispatches_guard()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
declare
  v_bad          text;
  v_target_type  text;
  v_target_super uuid;
begin
  v_bad := app.kitchen_payload_offending_key(new.money_free_payload);
  if v_bad is not null then
    raise exception 'kitchen_print_dispatches: hostile payload key % rejected (money/PII/endpoint vocabulary is forbidden at every nesting level)', v_bad
      using errcode = '23514';
  end if;
  if pg_column_size(new.money_free_payload) > 32768 then
    raise exception 'kitchen_print_dispatches: payload exceeds the 32KB limit'
      using errcode = '23514';
  end if;
  -- ORDER-EDIT-001A: WRITE-ONCE pointer. Once set it can never change or be
  -- cleared.
  if tg_op = 'UPDATE'
     and old.superseded_by_dispatch_id is not null
     and new.superseded_by_dispatch_id is distinct from old.superseded_by_dispatch_id then
    raise exception 'kitchen_print_dispatches: superseded_by_dispatch_id is write-once'
      using errcode = '23514';
  end if;
  -- The shape checks run only while the pointer is being SET (on INSERT, or
  -- NULL -> value on UPDATE), so later status / claim / report updates of an
  -- already-superseded row are never re-checked against a target that may
  -- itself have been superseded since. Every edge points from an older row to
  -- a strictly newer dispatch of the same order, written under the order lock,
  -- so cycles stay impossible; readers only test IS NOT NULL and never walk.
  if new.superseded_by_dispatch_id is not null
     and (tg_op = 'INSERT' or old.superseded_by_dispatch_id is null) then
    if new.dispatch_type = 'void' then
      raise exception 'kitchen_print_dispatches: a VOID dispatch is never superseded'
        using errcode = '23514';
    end if;
    select d.dispatch_type, d.superseded_by_dispatch_id
      into v_target_type, v_target_super
      from public.kitchen_print_dispatches d
      where d.id = new.superseded_by_dispatch_id
        and d.organization_id = new.organization_id;
    if v_target_type is not null and v_target_type not in ('void', 'order_edit') then
      raise exception 'kitchen_print_dispatches: supersession target must be a VOID or ORDER_EDIT dispatch'
        using errcode = '23514';
    end if;
    if v_target_super is not null then
      raise exception 'kitchen_print_dispatches: the supersession target is itself superseded'
        using errcode = '23514';
    end if;
  end if;
  return new;
end;
$$;

comment on function app.kitchen_print_dispatches_guard() is
  'KITCHEN-MODE-001C1 + ORDER-EDIT-001A: BEFORE INSERT/UPDATE guard — recursive money-free/PII key enforcement (token-boundary matching on normalized keys) + ~32KB payload size cap + the ORDER-EDIT-001A supersession shape (replaces the CORRECTION-001 "chain length exactly 1" rule): superseded_by_dispatch_id is WRITE-ONCE (NULL -> value only; any later change raises 23514); the target must be a VOID or ORDER_EDIT dispatch of the same org+order (composite FK + no-self CHECK); "the target is itself unsuperseded" is checked only while the pointer is being set (INSERT or OLD pointer NULL), so later status/claim/report updates of a superseded row are not re-checked; a VOID row can never be superseded. Chains such as initial -> edit1 -> edit2 -> void are allowed; cycles are impossible (every edge points to a strictly newer dispatch of the same order, written under the order lock, and the pointer is write-once). Fail-closed: a hostile payload aborts the surrounding mutation.';

-- ----------------------------------------------------------------------------
-- 9. sync_operations.operation_type CHECK — + 'order.edit', 'order.edit_ack'
--    (the latest list from 20261006140000_pos_cash_drawer_manual_open_001
--    plus the two new values).
-- ----------------------------------------------------------------------------
alter table public.sync_operations drop constraint if exists sync_operations_operation_type_check;
alter table public.sync_operations add constraint sync_operations_operation_type_check
  check (operation_type in ('shift.open', 'order.submit', 'order.discount', 'payment.create', 'shift.close', 'order.status', 'order.void', 'order.table_move', 'menu.availability_set', 'table.status_set', 'table.link', 'table.unlink', 'order.void_ack', 'order.items_add', 'order.round_status', 'kiosk.order.submit', 'cash_drawer.no_sale_open', 'order.edit', 'order.edit_ack'));
