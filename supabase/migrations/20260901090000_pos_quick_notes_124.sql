-- ============================================================================
-- POS-QUICK-NOTES-124 - Dashboard-managed reusable quick notes for the POS
-- per-item note field (D-001/D-011/D-012/D-013/D-017/D-020; RISK R-003)
-- ============================================================================
-- WHAT THIS IS. A cashier already types a free-text note on a cart line
-- (`modifier-item-note` -> CartLine.note -> order_items.notes). In a real
-- service the same handful of notes are typed over and over. This migration
-- lets an owner/manager define those phrases ONCE in the Dashboard; the POS
-- then offers them as one-tap chips that paste ORDINARY TEXT into the very
-- same field.
--
-- WHAT THIS DELIBERATELY IS NOT. It is not a second note system. No preset id
-- is ever stored on an order, sent in an order payload, printed, or shown on a
-- kitchen ticket. `order_items.notes` produced by tapping chips is
-- byte-identical to the same text typed by hand. Consequently NOTHING here
-- touches orders, payments, pricing, tax, modifiers, sync, idempotency, KDS or
-- printing - and the customer-facing kiosk menu is untouched on purpose:
-- quick notes are staff shorthand.
--
-- SCOPE (v1, binding). RESTAURANT-WIDE: organization_id + restaurant_id, and
-- deliberately NO branch_id. The owner's requirement is that one list serves
-- every POS device of the restaurant. A branch override, if it is ever asked
-- for, must arrive as a separate additive feature rather than as a nullable
-- column nobody set.
--
-- CONTENTS
--   1. table `quick_note_presets` (+ RLS, grants, indexes)
--   2. app.upsert_quick_note_preset        (manager+, idempotent, audited)
--   3. app.soft_delete_quick_note_preset   (manager+, idempotent, audited)
--   4. app.reorder_quick_note_presets      (manager+, complete-set, audited)
--   5. thin public SECURITY INVOKER wrappers
--   6. app.pos_menu re-emitted with ONE additive key: quick_note_presets
--   7. grants - REPORT-123 is binding: BOTH layers, authenticated only
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. quick_note_presets
-- ----------------------------------------------------------------------------
create table quick_note_presets (
  id              uuid        not null default gen_random_uuid(),
  organization_id uuid        not null references organizations (id) on delete restrict,
  restaurant_id   uuid        not null,
  -- 60 characters is the STRICT contract, enforced here (layer 4), in the RPC
  -- (layer 3) and in the Dashboard field. It is smaller than the note field's
  -- own 140 so that two or three presets can be combined in one note.
  label           text        not null check (length(btrim(label)) > 0 and length(label) <= 60),
  display_order   integer     not null default 0,
  is_active       boolean     not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  primary key (id),
  unique (organization_id, id),
  foreign key (organization_id, restaurant_id)
    references restaurants (organization_id, id) on delete restrict
);

comment on table quick_note_presets is
  'POS-QUICK-NOTES-124: reusable note phrases an owner/manager defines for a restaurant, offered to the POS as one-tap chips above the EXISTING per-item note field. Pure input convenience - a preset never reaches an order row, an order payload, a kitchen ticket or a receipt, and order_items.notes stays byte-identical to a hand-typed note. Restaurant-wide in v1 (NO branch_id). NO money columns. is_active = owner switch; deleted_at = tombstone (D-020). Writes are manager+ RPCs only (D-011); direct DML is RLS-denied and unGRANTed.';
comment on column quick_note_presets.label is
  'The exact text pasted into the note field. Tenant-entered free text in any of ar/he/en (D-014) - never translated, never normalized beyond OUTER whitespace trimming. Max 60 characters.';
comment on column quick_note_presets.display_order is
  'Owner-controlled chip order in the POS (0-based, dense; app.reorder_quick_note_presets owns it - an edit never changes it).';

-- One LIVE label per restaurant, case-insensitively: "No onions" and
-- "no onions" as two chips would be an owner mistake, not a feature. PARTIAL on
-- purpose - a tombstoned label becomes available again.
create unique index quick_note_presets_live_label_key
  on quick_note_presets (organization_id, restaurant_id, lower(label))
  where deleted_at is null;

create index quick_note_presets_org_rest_idx
  on quick_note_presets (organization_id, restaurant_id);

create trigger quick_note_presets_set_updated_at before update on quick_note_presets
  for each row execute function app.set_updated_at();

alter table quick_note_presets enable row level security;
alter table quick_note_presets force  row level security;

-- Restaurant-wide rows: has_scope is asked about the restaurant with a NULL
-- branch, which it reads as "any branch of it".
create policy quick_note_presets_sel on quick_note_presets for select to authenticated
  using (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, null));
create policy quick_note_presets_ins_deny on quick_note_presets for insert to authenticated with check (false);
create policy quick_note_presets_upd_deny on quick_note_presets for update to authenticated using (false) with check (false);
create policy quick_note_presets_del_deny on quick_note_presets for delete to authenticated using (false);

grant select on quick_note_presets to authenticated;   -- reads only; writes are NEVER granted

-- ----------------------------------------------------------------------------
-- 2. app.upsert_quick_note_preset - create / rename / enable / disable.
--    RF-112 manager template: ledger idempotency, denial audit, success audit.
--    display_order: a CREATE appends after the current live maximum; an UPDATE
--    never touches it (reorder owns ordering).
--    AUTHORITY: actor_rank_in_scope(org, restaurant, NULL) - the same
--    downward-only coverage app.menu_guard applies to restaurant-scoped menu
--    rows. A BRANCH-scoped principal therefore has no authority over this
--    restaurant-wide configuration at all (42501), which is distinct from a
--    covering principal who merely outranks too low (permission_denied).
-- ----------------------------------------------------------------------------
create or replace function app.upsert_quick_note_preset(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_id                uuid    default null,
  p_label             text    default null,
  p_is_active         boolean default true
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor        uuid := app.current_app_user_id();
  v_label        text := btrim(coalesce(p_label, ''));
  v_active       boolean := coalesce(p_is_active, true);
  v_found_org    uuid;
  v_found_rest   uuid;
  v_found_label  text;
  v_found_active boolean;
  v_found_del    timestamptz;
  v_id           uuid;
  v_action       text;
  v_rank         integer;
  v_fp           text;
  v_replay       jsonb;
  v_result       jsonb;
  v_old          jsonb;
  v_new          jsonb;
begin
  if v_actor is null then
    raise exception 'upsert_quick_note_preset: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'upsert_quick_note_preset: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null then
    raise exception 'upsert_quick_note_preset: organization_id and restaurant_id are required' using errcode = '42501';
  end if;
  if length(v_label) = 0 then
    raise exception 'upsert_quick_note_preset: label is required' using errcode = '42501';
  end if;
  -- STRICT: a too-long preset is refused, never silently truncated. Truncation
  -- would put words in the restaurant's mouth on a printed kitchen ticket.
  if length(v_label) > 60 then
    raise exception 'upsert_quick_note_preset: label must be at most 60 characters' using errcode = '42501';
  end if;
  if not exists (
       select 1 from public.restaurants r
       where r.id = p_restaurant_id and r.organization_id = p_organization_id
         and r.deleted_at is null) then
    raise exception 'upsert_quick_note_preset: restaurant not found in organization or is soft-deleted' using errcode = '42501';
  end if;

  if p_id is not null then
    select organization_id, restaurant_id, label, is_active, deleted_at
      into v_found_org, v_found_rest, v_found_label, v_found_active, v_found_del
      from public.quick_note_presets where id = p_id;
    if v_found_org is not null then
      if v_found_org <> p_organization_id then
        raise exception 'upsert_quick_note_preset: id belongs to another organization' using errcode = '42501';
      end if;
      if v_found_rest is distinct from p_restaurant_id then
        raise exception 'upsert_quick_note_preset: organization/restaurant are immutable on update' using errcode = '42501';
      end if;
      if v_found_del is not null then
        raise exception 'upsert_quick_note_preset: preset is deleted' using errcode = '42501';
      end if;
    end if;
  end if;

  v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id,
              'id', p_id, 'label', v_label, 'active', v_active)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'upsert_quick_note_preset', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, null);
  if v_rank = 0 then
    raise exception 'upsert_quick_note_preset: caller has no active membership covering the restaurant scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    perform app.management_audit(p_organization_id, p_restaurant_id, null,
      'quick_note_preset.upsert_denied', null,
      jsonb_build_object('entity', 'quick_note_preset', 'id', p_id, 'label', v_label));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'quick_note_preset');
  end if;

  -- The partial unique index is the real boundary; this check exists so the
  -- Dashboard receives a NAMED reason it can render instead of a raw 23505.
  if exists (
       select 1 from public.quick_note_presets q
       where q.organization_id = p_organization_id
         and q.restaurant_id = p_restaurant_id
         and q.deleted_at is null
         and lower(q.label) = lower(v_label)
         and (p_id is null or q.id <> p_id)) then
    return jsonb_build_object('ok', false, 'error', 'duplicate_label', 'entity', 'quick_note_preset');
  end if;

  if p_id is null or v_found_org is null then
    v_id := coalesce(p_id, gen_random_uuid());
    v_action := 'created';
  elsif v_found_label = v_label and v_found_active = v_active then
    v_id := p_id;
    v_action := 'unchanged';
  else
    v_id := p_id;
    v_action := 'updated';
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'quick_note_preset',
                'id', v_id, 'action', v_action);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'upsert_quick_note_preset', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  -- A no-op edit is an idempotent success that writes NO audit event: an audit
  -- trail that records changes which did not happen is worse than none.
  if v_action = 'unchanged' then
    return v_result;
  end if;

  if v_action = 'created' then
    insert into public.quick_note_presets (id, organization_id, restaurant_id, label, display_order, is_active)
    values (v_id, p_organization_id, p_restaurant_id, v_label,
            -- append after the current live siblings; never reuses a slot.
            coalesce((select max(q.display_order) + 1 from public.quick_note_presets q
                       where q.organization_id = p_organization_id
                         and q.restaurant_id   = p_restaurant_id
                         and q.deleted_at is null), 0),
            v_active);
  else
    select to_jsonb(q) into v_old from public.quick_note_presets q where q.id = v_id;
    update public.quick_note_presets set label = v_label, is_active = v_active where id = v_id;
  end if;

  select to_jsonb(q) into v_new from public.quick_note_presets q where q.id = v_id;
  perform app.management_audit(p_organization_id, p_restaurant_id, null,
    'quick_note_preset.' || v_action, v_old, v_new);
  return v_result;
end;
$$;

-- ----------------------------------------------------------------------------
-- 3. app.soft_delete_quick_note_preset - tombstone only (D-020). Nothing else
--    references a preset, so there is no detach step: removing a chip can never
--    disturb an order, past or open, because the text was copied at tap time.
-- ----------------------------------------------------------------------------
create or replace function app.soft_delete_quick_note_preset(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_preset_id         uuid
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor  uuid := app.current_app_user_id();
  v_org    uuid;
  v_rest   uuid;
  v_del    timestamptz;
  v_rank   integer;
  v_fp     text;
  v_replay jsonb;
  v_result jsonb;
  v_old    jsonb;
begin
  if v_actor is null then
    raise exception 'soft_delete_quick_note_preset: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'soft_delete_quick_note_preset: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_preset_id is null then
    raise exception 'soft_delete_quick_note_preset: organization_id and preset_id are required' using errcode = '42501';
  end if;

  -- The row is located WITHOUT the deleted_at filter on purpose: a retry of a
  -- delete that already succeeded must reach the idempotency ledger below and
  -- replay its stored result. Filtering tombstones out here would turn every
  -- retried delete - the ordinary consequence of a dropped response - into a
  -- 42501 the Dashboard would report as a failure of something that worked.
  select organization_id, restaurant_id, deleted_at into v_org, v_rest, v_del
    from public.quick_note_presets where id = p_preset_id;
  if v_org is null then
    raise exception 'soft_delete_quick_note_preset: preset not found' using errcode = '42501';
  end if;
  if v_org <> p_organization_id then
    raise exception 'soft_delete_quick_note_preset: preset belongs to another organization' using errcode = '42501';
  end if;

  v_fp := md5(jsonb_build_object('org', v_org, 'preset', p_preset_id)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'soft_delete_quick_note_preset', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  -- A DIFFERENT request deleting an already-tombstoned preset is a genuine
  -- mistake, not a retry, and is refused.
  if v_del is not null then
    raise exception 'soft_delete_quick_note_preset: preset is already deleted' using errcode = '42501';
  end if;

  v_rank := app.actor_rank_in_scope(v_org, v_rest, null);
  if v_rank = 0 then
    raise exception 'soft_delete_quick_note_preset: caller has no active membership covering the restaurant scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    perform app.management_audit(v_org, v_rest, null,
      'quick_note_preset.delete_denied', null,
      jsonb_build_object('entity', 'quick_note_preset', 'id', p_preset_id));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'quick_note_preset');
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', 'quick_note_preset',
                'id', p_preset_id, 'action', 'deleted');
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'soft_delete_quick_note_preset', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  select to_jsonb(q) into v_old from public.quick_note_presets q where q.id = p_preset_id;
  update public.quick_note_presets set deleted_at = now() where id = p_preset_id;

  perform app.management_audit(v_org, v_rest, null, 'quick_note_preset.deleted', v_old,
    jsonb_build_object('id', p_preset_id, 'deleted', true));
  return v_result;
end;
$$;

-- ----------------------------------------------------------------------------
-- 4. app.reorder_quick_note_presets - the chip order the cashier sees.
--    Complete-live-set validation, exactly as reorder_table_sections: a partial
--    list would silently invent an order for the presets it omitted.
-- ----------------------------------------------------------------------------
create or replace function app.reorder_quick_note_presets(
  p_organization_id uuid,
  p_restaurant_id   uuid,
  p_ids             uuid[]
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor uuid := app.current_app_user_id();
  v_rank  integer;
  v_n     integer;
  v_found integer;
  v_total integer;
begin
  if v_actor is null then
    raise exception 'reorder_quick_note_presets: invalid request' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null then
    raise exception 'reorder_quick_note_presets: invalid request' using errcode = '42501';
  end if;

  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, null);
  if v_rank = 0 then
    raise exception 'reorder_quick_note_presets: invalid request' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    perform app.management_audit(p_organization_id, p_restaurant_id, null,
      'quick_note_preset.reorder_denied', null, jsonb_build_object('entity', 'quick_note_preset'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'quick_note_preset');
  end if;

  -- input shape: non-empty, distinct, and EXACTLY the live sibling set
  -- (disabled-but-live presets included - they still hold a slot).
  v_n := coalesce(array_length(p_ids, 1), 0);
  if v_n = 0 then
    raise exception 'reorder_quick_note_presets: invalid request' using errcode = '42501';
  end if;
  if (select count(distinct u) from unnest(p_ids) u) <> v_n then
    raise exception 'reorder_quick_note_presets: invalid request' using errcode = '42501';
  end if;
  select count(*) into v_found
    from public.quick_note_presets q
    where q.organization_id = p_organization_id
      and q.restaurant_id   = p_restaurant_id
      and q.deleted_at is null
      and q.id = any(p_ids);
  select count(*) into v_total
    from public.quick_note_presets q
    where q.organization_id = p_organization_id
      and q.restaurant_id   = p_restaurant_id
      and q.deleted_at is null;
  if v_found <> v_n or v_total <> v_n then
    raise exception 'reorder_quick_note_presets: invalid request' using errcode = '42501';
  end if;

  update public.quick_note_presets q
     set display_order = ord.position - 1
    from (select u.id, u.ordinality as position
            from unnest(p_ids) with ordinality as u(id, ordinality)) ord
   where q.id = ord.id
     and q.organization_id = p_organization_id;

  perform app.management_audit(p_organization_id, p_restaurant_id, null,
    'quick_note_preset.reordered', null, jsonb_build_object('ids', to_jsonb(p_ids)));
  return jsonb_build_object('ok', true, 'entity', 'quick_note_preset', 'action', 'reordered',
                            'count', v_n);
end;
$$;

-- ----------------------------------------------------------------------------
-- 4b. app.list_quick_note_presets - what the DASHBOARD reads.
--     Deliberately NOT the same projection as app.pos_menu: the manager needs
--     to see a preset they have SWITCHED OFF (to switch it back on), while a
--     cashier must not be offered it. Tombstones are excluded from both.
--     Manager+, matching app.list_tables - this is a configuration surface.
-- ----------------------------------------------------------------------------
create or replace function app.list_quick_note_presets(
  p_organization_id uuid,
  p_restaurant_id   uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor   uuid := app.current_app_user_id();
  v_rank    integer;
  v_presets jsonb;
begin
  if v_actor is null then
    raise exception 'list_quick_note_presets: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null then
    raise exception 'list_quick_note_presets: organization_id and restaurant_id are required' using errcode = '42501';
  end if;

  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, null);
  if v_rank = 0 then
    raise exception 'list_quick_note_presets: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'quick_note_preset');
  end if;

  select coalesce(jsonb_agg(
           jsonb_build_object('id', q.id, 'label', q.label,
                              'display_order', q.display_order, 'is_active', q.is_active)
           order by q.display_order, q.label), '[]'::jsonb)
    into v_presets
    from public.quick_note_presets q
    where q.organization_id = p_organization_id
      and q.restaurant_id   = p_restaurant_id
      and q.deleted_at is null;

  return jsonb_build_object('ok', true, 'entity', 'quick_note_preset',
                            'presets', v_presets);
end;
$$;

-- ----------------------------------------------------------------------------
-- 5. Thin public SECURITY INVOKER wrappers (RF-064 / RF-109 / RF-160 pattern).
-- ----------------------------------------------------------------------------
create or replace function public.upsert_quick_note_preset(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid,
  p_id uuid default null, p_label text default null, p_is_active boolean default true)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.upsert_quick_note_preset(p_client_request_id, p_organization_id, p_restaurant_id, p_id, p_label, p_is_active); $$;

create or replace function public.soft_delete_quick_note_preset(
  p_client_request_id uuid, p_organization_id uuid, p_preset_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.soft_delete_quick_note_preset(p_client_request_id, p_organization_id, p_preset_id); $$;

create or replace function public.reorder_quick_note_presets(
  p_organization_id uuid, p_restaurant_id uuid, p_ids uuid[])
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.reorder_quick_note_presets(p_organization_id, p_restaurant_id, p_ids); $$;

create or replace function public.list_quick_note_presets(
  p_organization_id uuid, p_restaurant_id uuid)
  returns jsonb language sql stable security invoker set search_path = ''
as $$ select app.list_quick_note_presets(p_organization_id, p_restaurant_id); $$;

-- ----------------------------------------------------------------------------
-- 6. app.pos_menu - re-emitted VERBATIM from 20260820090000 (OPS-044) with ONE
--    additive change: a `quick_note_presets` array. Every existing key, filter,
--    join, redaction rule and ordering is byte-for-byte the same; the public
--    wrapper's signature is unchanged, so it is not re-emitted.
-- ----------------------------------------------------------------------------
create or replace function app.pos_menu(
  p_pin_session_id uuid,
  p_device_id      uuid
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_org        uuid;
  v_rest       uuid;
  v_branch     uuid;
  v_dsid       uuid;
  v_emp        uuid;
  v_membership uuid;
  v_ds_device  uuid;
  v_ds_active  boolean;
  v_ds_revoked timestamptz;
  v_pairing    text;
  v_role       text;
  v_m_status   text;
  v_m_deleted  timestamptz;
  v_redact     boolean;
  v_currency   text;
  v_categories jsonb;
  v_items      jsonb;
  v_sizes      jsonb;
  v_variants   jsonb;
  v_modifiers  jsonb;
  v_options    jsonb;
  v_quick      jsonb;
begin
  -- (a) PIN session + backing device session/pairing active; device match (A8).
  --     Scope (org/restaurant/branch) + actor + role are derived HERE, never from payload.
  select ps.organization_id, ps.restaurant_id, ps.branch_id, ps.device_session_id,
         ps.employee_profile_id, ps.resolved_membership_id
    into v_org, v_rest, v_branch, v_dsid, v_emp, v_membership
    from public.pin_sessions ps where ps.id = p_pin_session_id;
  if not found then
    raise exception 'pos_menu: PIN session not found' using errcode = '42501';
  end if;
  if not app.is_pin_session_valid(p_pin_session_id) then
    raise exception 'pos_menu: PIN session is not valid (inactive/ended/expired)' using errcode = '42501';
  end if;
  select ds.device_id, ds.is_active, ds.revoked_at, dp.status
    into v_ds_device, v_ds_active, v_ds_revoked, v_pairing
    from public.device_sessions ds join public.device_pairings dp on dp.id = ds.device_pairing_id
    where ds.id = v_dsid;
  if not found or not (v_ds_active and v_ds_revoked is null and v_pairing = 'active') then
    raise exception 'pos_menu: backing device session/pairing is not active' using errcode = '42501';
  end if;
  if v_ds_device <> p_device_id then
    raise exception 'pos_menu: device_id does not match the PIN session device' using errcode = '42501';
  end if;
  select m.role, m.status, m.deleted_at
    into v_role, v_m_status, v_m_deleted
    from public.memberships m where m.id = v_membership and m.organization_id = v_org;
  if not found or v_m_status <> 'active' or v_m_deleted is not null then
    raise exception 'pos_menu: resolved membership is not active' using errcode = '42501';
  end if;

  -- (b) T-003 money redaction: a kitchen principal never receives a money figure.
  --     base_price_minor (items) AND price_delta_minor (sizes/variants/options)
  --     KEYS are omitted (not nulled) below. The SAME kitchen principal also
  --     never receives image_path (T-014). Menu/media sprint: item_type/tags/
  --     prep_minutes/kitchen_note/attributes are NON-MONEY and pass through to
  --     kitchen too — that is exactly the prep info a KDS needs.
  v_redact := (v_role = 'kitchen_staff');

  -- (c) the REAL tenant currency: restaurants.currency_override, else the
  --     organization default (matches app.list_menu).
  select coalesce(r.currency_override, o.default_currency)
    into v_currency
    from public.restaurants r
    join public.organizations o on o.id = r.organization_id
    where r.id = v_rest and r.organization_id = v_org;

  -- (d) live categories of the session restaurant, branch-visible
  --     (branch_id null = restaurant-scoped, or the session branch). Tombstoned
  --     (deleted_at) and inactive rows are excluded — this is the LIVE sell menu,
  --     not the sync feed (tombstone propagation stays with sync_pull, D-020).
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

  -- (e) live items: item live + branch-visible AND parent category live +
  --     branch-visible. base_price_minor is integer minor (bigint; D-007) and is
  --     OMITTED entirely for kitchen_staff (T-003); image_path is likewise
  --     OMITTED for kitchen_staff (T-014). item_type/tags/prep_minutes/
  --     kitchen_note/attributes are non-money and serve BOTH branches; sku is
  --     an internal back-office code and is NEVER served to devices.
  --     RESTAURANT-OPERATIONS-V1-001: every item additionally carries its
  --     SESSION-BRANCH availability ('available' when no override row exists)
  --     + availability_reason — unavailable items stay in the payload so the
  --     POS can show WHY they cannot be sold (they are excluded from SALE by
  --     app.submit_order, not from sight).
  select coalesce(jsonb_agg(
           case when v_redact then
             jsonb_build_object(
               'id', i.id, 'menu_category_id', i.menu_category_id, 'name', i.name,
               'description', i.description, 'display_order', i.display_order,
               'default_station_id', i.default_station_id,
               'item_type', i.item_type, 'tags', i.tags,
               'prep_minutes', i.prep_minutes, 'kitchen_note', i.kitchen_note,
               'attributes', i.attributes,
               'availability', coalesce(a.availability, 'available'),
               'availability_reason', a.reason)
           else
             jsonb_build_object(
               'id', i.id, 'menu_category_id', i.menu_category_id, 'name', i.name,
               'description', i.description, 'display_order', i.display_order,
               'default_station_id', i.default_station_id,
               'item_type', i.item_type, 'tags', i.tags,
               'prep_minutes', i.prep_minutes, 'kitchen_note', i.kitchen_note,
               'attributes', i.attributes,
               'base_price_minor', i.base_price_minor,
               'image_path', i.image_path,
               'availability', coalesce(a.availability, 'available'),
               'availability_reason', a.reason)
           end
           order by i.display_order, i.name), '[]'::jsonb)
    into v_items
    from public.menu_items i
    join public.menu_categories c
      -- REVIEW DELTA (HIGH): the category must belong to the EXACT restaurant
      -- scope — an item referencing a sibling restaurant's category (legal at
      -- the schema level within one org) is NOT part of this menu.
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

  -- (f) live sizes of LIVE items (parent chain: size live + branch-visible,
  --     item live + branch-visible, item's category live + branch-visible).
  --     price_delta_minor is SIGNED integer minor (D-007); OMITTED for kitchen.
  select coalesce(jsonb_agg(
           case when v_redact then
             jsonb_build_object(
               'id', s.id, 'menu_item_id', s.menu_item_id, 'name', s.name,
               'display_order', s.display_order)
           else
             jsonb_build_object(
               'id', s.id, 'menu_item_id', s.menu_item_id, 'name', s.name,
               'display_order', s.display_order,
               'price_delta_minor', s.price_delta_minor)
           end
           order by s.display_order, s.name), '[]'::jsonb)
    into v_sizes
    from public.item_sizes s
    join public.menu_items i
      on i.organization_id = s.organization_id
     and i.restaurant_id   = v_rest
     and i.id = s.menu_item_id
    join public.menu_categories c
      -- REVIEW DELTA (HIGH): the category must belong to the EXACT restaurant
      -- scope — an item referencing a sibling restaurant's category (legal at
      -- the schema level within one org) is NOT part of this menu.
      on c.organization_id = i.organization_id
     and c.restaurant_id   = v_rest
     and c.id = i.menu_category_id
    where s.organization_id = v_org
      and s.restaurant_id = v_rest
      and s.is_active
      and s.deleted_at is null
      and (s.branch_id is null or s.branch_id = v_branch)
      and i.is_active and i.deleted_at is null and (i.branch_id is null or i.branch_id = v_branch)
      and c.is_active and c.deleted_at is null and (c.branch_id is null or c.branch_id = v_branch);

  -- (g) live variants of LIVE items — same filters/shape as sizes.
  select coalesce(jsonb_agg(
           case when v_redact then
             jsonb_build_object(
               'id', v.id, 'menu_item_id', v.menu_item_id, 'name', v.name,
               'display_order', v.display_order)
           else
             jsonb_build_object(
               'id', v.id, 'menu_item_id', v.menu_item_id, 'name', v.name,
               'display_order', v.display_order,
               'price_delta_minor', v.price_delta_minor)
           end
           order by v.display_order, v.name), '[]'::jsonb)
    into v_variants
    from public.item_variants v
    join public.menu_items i
      on i.organization_id = v.organization_id
     and i.restaurant_id   = v_rest
     and i.id = v.menu_item_id
    join public.menu_categories c
      -- REVIEW DELTA (HIGH): the category must belong to the EXACT restaurant
      -- scope — an item referencing a sibling restaurant's category (legal at
      -- the schema level within one org) is NOT part of this menu.
      on c.organization_id = i.organization_id
     and c.restaurant_id   = v_rest
     and c.id = i.menu_category_id
    where v.organization_id = v_org
      and v.restaurant_id = v_rest
      and v.is_active
      and v.deleted_at is null
      and (v.branch_id is null or v.branch_id = v_branch)
      and i.is_active and i.deleted_at is null and (i.branch_id is null or i.branch_id = v_branch)
      and c.is_active and c.deleted_at is null and (c.branch_id is null or c.branch_id = v_branch);

  -- (h) live modifiers of LIVE items (money-free rows — selection rules only).
  --     MVP quantity settings: allow_quantity + max_quantity are COUNTS (never
  --     money, D-007) and serve EVERY role incl. kitchen — consistent with
  --     selection_type/min_select/max_select already served here.
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
      -- REVIEW DELTA (HIGH): the category must belong to the EXACT restaurant
      -- scope — an item referencing a sibling restaurant's category (legal at
      -- the schema level within one org) is NOT part of this menu.
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

  -- (i) live options of LIVE modifiers (full parent chain: option live +
  --     branch-visible, modifier live + branch-visible, modifier's item live +
  --     branch-visible, item's category live + branch-visible). price_delta_minor
  --     OMITTED for kitchen (T-003).
  select coalesce(jsonb_agg(
           case when v_redact then
             jsonb_build_object(
               'id', mo.id, 'modifier_id', mo.modifier_id, 'name', mo.name,
               'display_order', mo.display_order, 'kitchen_meat', mo.kitchen_meat)
           else
             jsonb_build_object(
               'id', mo.id, 'modifier_id', mo.modifier_id, 'name', mo.name,
               'display_order', mo.display_order,
               'price_delta_minor', mo.price_delta_minor, 'kitchen_meat', mo.kitchen_meat)
           end
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
      -- REVIEW DELTA (HIGH): the category must belong to the EXACT restaurant
      -- scope — an item referencing a sibling restaurant's category (legal at
      -- the schema level within one org) is NOT part of this menu.
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

  -- (j) POS-QUICK-NOTES-124: the restaurant's reusable note presets. These are
  --     an INPUT CONVENIENCE for the existing per-item note field - they carry
  --     no price, no order identity and no tenant metadata, so they are served
  --     to EVERY role including kitchen (a kitchen principal simply has no note
  --     field to paste them into). Restaurant-wide by design: v1 has no branch
  --     dimension, so every POS device of the restaurant shows the same chips.
  --     Live (deleted_at is null) AND enabled (is_active) only - a disabled
  --     preset is configuration the owner switched off, not a tombstone.
  select coalesce(jsonb_agg(
           jsonb_build_object('id', q.id, 'label', q.label, 'display_order', q.display_order)
           order by q.display_order, q.label), '[]'::jsonb)
    into v_quick
    from public.quick_note_presets q
    where q.organization_id = v_org
      and q.restaurant_id = v_rest
      and q.is_active
      and q.deleted_at is null;

  return jsonb_build_object(
    'ok', true,
    'entity', 'menu',
    'currency_code', v_currency,
    'categories', v_categories,
    'items', v_items,
    'sizes', v_sizes,
    'variants', v_variants,
    'modifiers', v_modifiers,
    'modifier_options', v_options,
    'quick_note_presets', v_quick,
    'server_ts', now());
end;
$$;

comment on function app.pos_menu(uuid, uuid) is
  'POS/KDS live sell menu for a PIN session on a paired device. POS-QUICK-NOTES-124 adds ONE additive top-level key, quick_note_presets ({id, label, display_order}, live + enabled + this restaurant, display-ordered): reusable note phrases the POS offers as one-tap chips above the EXISTING per-item note field. They are input convenience only - no money, no order identity - so they are served to every role. Existing keys and semantics are unchanged; a client that does not know the key ignores it, and a client that does treats a missing key as "no chips".';

-- ----------------------------------------------------------------------------
-- 7. Grants - authenticated only (never anon / service_role; D-011).
--
--    REPORT-123 IS BINDING HERE. The public wrappers are SECURITY INVOKER: they
--    run with the CALLER's privileges and delegate to the SECURITY DEFINER
--    implementation. Granting only the wrapper grants NOTHING - the caller is
--    refused on the inner function with 42501. Both layers are granted below,
--    and supabase/tests/pos_quick_notes_124_test.sql pins both as the real
--    `authenticated` ROLE (a suite that only sets the identity GUC executes as
--    superuser and would not notice the omission).
-- ----------------------------------------------------------------------------
revoke all on function app.upsert_quick_note_preset(uuid, uuid, uuid, uuid, text, boolean) from public;
revoke all on function app.soft_delete_quick_note_preset(uuid, uuid, uuid)                 from public;
revoke all on function app.reorder_quick_note_presets(uuid, uuid, uuid[])                  from public;
revoke all on function app.list_quick_note_presets(uuid, uuid)                             from public;
grant execute on function app.upsert_quick_note_preset(uuid, uuid, uuid, uuid, text, boolean) to authenticated;
grant execute on function app.soft_delete_quick_note_preset(uuid, uuid, uuid)                 to authenticated;
grant execute on function app.reorder_quick_note_presets(uuid, uuid, uuid[])                  to authenticated;
grant execute on function app.list_quick_note_presets(uuid, uuid)                             to authenticated;

revoke all on function public.upsert_quick_note_preset(uuid, uuid, uuid, uuid, text, boolean) from public;
revoke all on function public.soft_delete_quick_note_preset(uuid, uuid, uuid)                 from public;
revoke all on function public.reorder_quick_note_presets(uuid, uuid, uuid[])                  from public;
revoke all on function public.list_quick_note_presets(uuid, uuid)                             from public;
grant execute on function public.upsert_quick_note_preset(uuid, uuid, uuid, uuid, text, boolean) to authenticated;
grant execute on function public.soft_delete_quick_note_preset(uuid, uuid, uuid)                 to authenticated;
grant execute on function public.reorder_quick_note_presets(uuid, uuid, uuid[])                  to authenticated;
grant execute on function public.list_quick_note_presets(uuid, uuid)                             to authenticated;

comment on function app.upsert_quick_note_preset(uuid, uuid, uuid, uuid, text, boolean) is
  'POS-QUICK-NOTES-124: create/rename/enable/disable a restaurant quick-note preset. Manager+ over the RESTAURANT-wide scope (a branch-scoped principal is refused outright, per the downward-only coverage app.menu_guard applies). Trims outer whitespace, preserves inner text exactly, refuses >60 characters rather than truncating, refuses a live duplicate label with error=duplicate_label. Ledger-idempotent; a no-op edit returns action=unchanged and writes NO audit event.';
comment on function app.soft_delete_quick_note_preset(uuid, uuid, uuid) is
  'POS-QUICK-NOTES-124: tombstone a quick-note preset (D-020). Manager+, ledger-idempotent, audited. Removing a chip cannot disturb any order - the text was copied into order_items.notes at tap time.';
comment on function app.reorder_quick_note_presets(uuid, uuid, uuid[]) is
  'POS-QUICK-NOTES-124: set the POS chip order. Manager+, audited. Requires the COMPLETE live set (disabled-but-live presets included); a partial, duplicated or foreign list is refused with 42501 rather than inventing an order.';
comment on function app.list_quick_note_presets(uuid, uuid) is
  'POS-QUICK-NOTES-124: the DASHBOARD read - live presets of one restaurant, display-ordered, DISABLED ONES INCLUDED (a manager must see what they switched off in order to switch it back on). Tombstones excluded. Manager+, read-only, money-free. Deliberately a different projection from app.pos_menu, which serves only what a cashier may actually tap.';

-- ----------------------------------------------------------------------------
-- 8. Realtime: NOT published. Quick notes arrive with the next menu read, which
--    already happens on every POS load and reconnect. A dedicated channel (or
--    polling) would add a live dependency to a settings list that changes a few
--    times a year, and an offline till would still fall back to its snapshot.
-- ----------------------------------------------------------------------------
