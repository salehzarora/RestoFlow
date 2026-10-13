-- POS-ONLINE-INBOX-001 / D-046. Local implementation only; enables no channel.
-- New authenticated RPCs reuse the unchanged canonical app.sync_push path.
begin;

create table public.web_order_decisions (
  organization_id uuid not null,
  restaurant_id uuid not null,
  branch_id uuid not null,
  request_id uuid primary key,
  decision_id uuid not null,
  decision text not null check (decision in ('accepted','rejected')),
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  device_id uuid not null,
  pin_session_id uuid not null,
  employee_profile_id uuid not null,
  resolved_membership_id uuid not null,
  shift_id uuid,
  canonical_order_id uuid,
  decided_at timestamptz not null,
  constraint web_order_decisions_identity_key
    unique (organization_id, restaurant_id, branch_id, decision_id),
  foreign key (organization_id, restaurant_id, branch_id, request_id)
    references public.web_order_requests (organization_id, restaurant_id, branch_id, id)
    on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id, device_id)
    references public.devices (organization_id, restaurant_id, branch_id, id)
    on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id, pin_session_id)
    references public.pin_sessions (organization_id, restaurant_id, branch_id, id)
    on delete restrict,
  foreign key (organization_id, employee_profile_id)
    references public.employee_profiles (organization_id, id) on delete restrict,
  foreign key (organization_id, resolved_membership_id)
    references public.memberships (organization_id, id) on delete restrict,
  foreign key (organization_id, shift_id)
    references public.shifts (organization_id, id) on delete restrict,
  foreign key (organization_id, canonical_order_id)
    references public.orders (organization_id, id) on delete restrict,
  check ((decision = 'accepted') = (canonical_order_id is not null)),
  check ((decision = 'accepted') = (shift_id is not null))
);
alter table public.web_order_decisions enable row level security;
alter table public.web_order_decisions force row level security;
create policy web_order_decisions_select on public.web_order_decisions
  for select to authenticated using (false);
create policy web_order_decisions_insert on public.web_order_decisions
  for insert to authenticated with check (false);
create policy web_order_decisions_update on public.web_order_decisions
  for update to authenticated using (false) with check (false);
create policy web_order_decisions_delete on public.web_order_decisions
  for delete to authenticated using (false);
revoke all on public.web_order_decisions from public, anon, authenticated, service_role;
create trigger web_order_decisions_append_only
  before update or delete on public.web_order_decisions
  for each row execute function app.enforce_audit_append_only();
create trigger web_order_decisions_no_truncate
  before truncate on public.web_order_decisions
  for each statement execute function app.enforce_audit_append_only();
comment on table public.web_order_decisions is
  'POS-ONLINE-INBOX-001: private append-only real-staff terminal decision ledger. One decision per request, full-scope decision identity and SQL-only fingerprint. No customer contact, free-text reason, capability or device token. Canonical order audit remains on app.sync_push.';

-- Internal only. The authenticated anonymous GoTrue principal is the transport
-- envelope, never the human staff authority and never a membership comparison.
create function app.pos_web_order_context(
  p_pin_session_id uuid, p_device_id uuid, p_device_session_token text
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_proof jsonb;
  v_pin public.pin_sessions;
  v_locked_pin public.pin_sessions;
  v_employee public.employee_profiles;
  v_initial_employee public.employee_profiles;
  v_membership public.memberships;
  v_now timestamptz;
  v_count integer;
begin
  if auth.uid() is null or p_pin_session_id is null or p_device_id is null
     or p_device_session_token is null or length(p_device_session_token) > 4096
     or btrim(p_device_session_token) = '' then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  -- Holds the established hierarchy locks: org, restaurant, branch, device,
  -- pairing, device session. Token proof precedes caller-selected row locks.
  v_proof := app.renew_device_session(p_device_id,p_device_session_token);
  if (v_proof->>'ok') is distinct from 'true' then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  if v_proof->>'device_type' is distinct from 'pos' then
    return jsonb_build_object('ok',false,'error','permission_denied');
  end if;
  if not exists (
    select 1 from public.organizations o
    join public.restaurants r on r.organization_id=o.id
    join public.branches b on b.organization_id=o.id and b.restaurant_id=r.id
    where o.id=(v_proof->>'organization_id')::uuid and o.status='active' and o.deleted_at is null
      and r.id=(v_proof->>'restaurant_id')::uuid and r.status='active' and r.deleted_at is null
      and b.id=(v_proof->>'branch_id')::uuid and b.status='active' and b.deleted_at is null
  ) then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  select * into v_pin from public.pin_sessions ps
    where ps.id=p_pin_session_id
      and ps.device_session_id=(v_proof->>'device_session_id')::uuid
      and ps.organization_id=(v_proof->>'organization_id')::uuid
      and ps.restaurant_id=(v_proof->>'restaurant_id')::uuid
      and ps.branch_id=(v_proof->>'branch_id')::uuid;
  if not found then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  select * into v_initial_employee from public.employee_profiles ep
    where ep.id=v_pin.employee_profile_id and ep.organization_id=v_pin.organization_id;
  if not found then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  -- The legacy documented fallback must still be unambiguous. Lock its parent
  -- before memberships: its FK also serializes new membership inserts.
  if v_initial_employee.membership_id is null and v_initial_employee.app_user_id is not null then
    perform 1 from public.app_users u where u.id=v_initial_employee.app_user_id for update;
  end if;
  -- Membership before employee matches the employee-revocation writer.
  select * into v_membership from public.memberships m
    where m.id=v_pin.resolved_membership_id and m.organization_id=v_pin.organization_id for share;
  if not found then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  select * into v_employee from public.employee_profiles ep
    where ep.id=v_pin.employee_profile_id and ep.organization_id=v_pin.organization_id for share;
  if not found then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  select * into v_locked_pin from public.pin_sessions ps
    where ps.id=p_pin_session_id for share;
  if not found or v_locked_pin.device_session_id is distinct from v_pin.device_session_id
     or v_locked_pin.employee_profile_id is distinct from v_pin.employee_profile_id
     or v_locked_pin.resolved_membership_id is distinct from v_pin.resolved_membership_id
     or v_locked_pin.organization_id is distinct from v_pin.organization_id
     or v_locked_pin.restaurant_id is distinct from v_pin.restaurant_id
     or v_locked_pin.branch_id is distinct from v_pin.branch_id then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  v_now := clock_timestamp();
  if not v_locked_pin.is_active or v_locked_pin.ended_at is not null
     or (v_locked_pin.expires_at is not null and v_locked_pin.expires_at<=v_now)
     or (v_proof->>'session_expires_at')::timestamptz<=v_now
     or v_employee.employment_status<>'active' or v_employee.deleted_at is not null
     or (v_employee.restaurant_id is not null and v_employee.restaurant_id<>v_pin.restaurant_id)
     or (v_employee.branch_id is not null and v_employee.branch_id<>v_pin.branch_id)
     or v_membership.status<>'active' or v_membership.deleted_at is not null
     or (v_membership.restaurant_id is not null and v_membership.restaurant_id<>v_pin.restaurant_id)
     or (v_membership.branch_id is not null and v_membership.branch_id<>v_pin.branch_id)
     or v_employee.membership_id is distinct from v_initial_employee.membership_id
     or v_employee.app_user_id is distinct from v_initial_employee.app_user_id then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  if v_employee.membership_id is not null then
    if v_employee.membership_id<>v_membership.id then
      return jsonb_build_object('ok',false,'error','invalid_session');
    end if;
  else
    if v_employee.app_user_id is null or v_membership.app_user_id<>v_employee.app_user_id then
      return jsonb_build_object('ok',false,'error','invalid_session');
    end if;
    select count(*) into v_count from public.memberships m
      where m.organization_id=v_pin.organization_id and m.app_user_id=v_employee.app_user_id
        and m.status='active' and m.deleted_at is null;
    if v_count<>1 then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  end if;
  if v_membership.role not in ('cashier','manager','restaurant_owner','org_owner') then
    return jsonb_build_object('ok',false,'error','permission_denied');
  end if;
  return v_proof || jsonb_build_object('employee_profile_id',v_employee.id,
    'resolved_membership_id',v_membership.id,'pin_expires_at',v_locked_pin.expires_at);
end;
$$;
revoke all on function app.pos_web_order_context(uuid,uuid,text)
  from public,anon,authenticated,service_role;

-- No private hashes or attribution identifiers are representable in this view.
create function app.pos_web_order_view(p_request public.web_order_requests,p_now timestamptz)
returns jsonb language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'request_id',p_request.id,
    'status',case when p_request.status='pending' and p_request.expires_at<=p_now
                  then 'expired' else p_request.status end,
    'customer',jsonb_build_object('name',p_request.customer_name,'phone',p_request.customer_phone),
    'notes',p_request.notes,'created_at',p_request.created_at,'expires_at',p_request.expires_at,
    'totals',jsonb_build_object('currency_code',p_request.currency_code,
      'subtotal_minor',p_request.subtotal_minor,'tax_total_minor',p_request.tax_total_minor,
      'grand_total_minor',p_request.grand_total_minor),
    'items',p_request.priced_items,'canonical_order_id',p_request.canonical_order_id);
$$;
revoke all on function app.pos_web_order_view(public.web_order_requests,timestamptz)
  from public,anon,authenticated,service_role;

create function app.pos_web_order_inbox(
  p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,
  p_request_id uuid default null,p_before_created_at timestamptz default null,
  p_before_id uuid default null,p_limit integer default 50
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_context jsonb;
  v_request public.web_order_requests;
  v_now timestamptz;
  v_rows jsonb;
  v_count integer;
  v_has_more boolean;
  v_cursor jsonb;
begin
  v_context:=app.pos_web_order_context(p_pin_session_id,p_device_id,p_device_session_token);
  if (v_context->>'ok') is distinct from 'true' then
    return jsonb_build_object('ok',false,'error',v_context->>'error','entity','web_order_request');
  end if;
  if p_limit is null or p_limit not between 1 and 50
     or (p_before_created_at is null)<>(p_before_id is null)
     or (p_before_created_at is not null and not isfinite(p_before_created_at))
     or (p_request_id is not null and p_before_id is not null) then
    return jsonb_build_object('ok',false,'error','invalid_request','entity','web_order_request');
  end if;
  if p_request_id is not null then
    -- A terminal reconciliation read must wait for an in-flight decision and
    -- read the committed row, rather than reporting its old pending snapshot.
    select * into v_request from public.web_order_requests w
      where w.id=p_request_id and w.organization_id=(v_context->>'organization_id')::uuid
        and w.restaurant_id=(v_context->>'restaurant_id')::uuid
        and w.branch_id=(v_context->>'branch_id')::uuid for share;
    if not found then
      return jsonb_build_object('ok',false,'error','not_found','entity','web_order_request');
    end if;
    v_now:=clock_timestamp();
    if (v_context->>'pin_expires_at')::timestamptz<=v_now
       or (v_context->>'session_expires_at')::timestamptz<=v_now then
      return jsonb_build_object('ok',false,'error','invalid_session','entity','web_order_request');
    end if;
    return jsonb_build_object('ok',true,'server_time',v_now,
      'requests',jsonb_build_array(app.pos_web_order_view(v_request,v_now)),
      'has_more',false,'next_cursor',null);
  end if;
  v_now:=clock_timestamp();
  select coalesce(jsonb_agg(app.pos_web_order_view(q.r,v_now)
           order by (q.r).created_at desc,(q.r).id desc),'[]'::jsonb),count(*)::integer
    into v_rows,v_count
    from (
      select w as r from public.web_order_requests w
      where w.organization_id=(v_context->>'organization_id')::uuid
        and w.restaurant_id=(v_context->>'restaurant_id')::uuid
        and w.branch_id=(v_context->>'branch_id')::uuid
        and w.status='pending' and w.expires_at>v_now
        and (p_before_created_at is null or (w.created_at,w.id)<(p_before_created_at,p_before_id))
      order by w.created_at desc,w.id desc limit p_limit+1
    ) q;
  v_has_more:=v_count>p_limit;
  if v_has_more then
    v_rows:=v_rows-p_limit;
    v_cursor:=jsonb_build_object('created_at',v_rows->(p_limit-1)->'created_at',
      'id',v_rows->(p_limit-1)->'request_id');
  end if;
  return jsonb_build_object('ok',true,'server_time',v_now,'requests',v_rows,
    'has_more',v_has_more,'next_cursor',v_cursor);
end;
$$;

-- Internal common decision transaction, never granted directly to clients.
-- Rejection shares authority/idempotency only; it never invokes canonical work.
create function app.decide_pos_web_order(
  p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,
  p_request_id uuid,p_decision_id uuid,p_decision text,p_reason text
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_context jsonb;
  v_request public.web_order_requests;
  v_decision public.web_order_decisions;
  v_used public.web_order_decisions;
  v_profile public.restaurant_storefront_profiles;
  v_shift_id uuid;
  v_reason text;
  v_payload_hash text;
  v_now timestamptz;
  v_items jsonb;
  v_quote jsonb;
  v_item jsonb;
  v_modifier jsonb;
  v_modifiers jsonb;
  v_canonical_items jsonb:='[]'::jsonb;
  v_item_ids uuid[];
  v_group_ids uuid[];
  v_group_name text;
  v_order_id uuid;
  v_operation_id text;
  v_payload jsonb;
  v_sync jsonb;
  v_result jsonb;
  v_error text;
  v_mode text;
  v_constraint text;
begin
  v_context:=app.pos_web_order_context(p_pin_session_id,p_device_id,p_device_session_token);
  if (v_context->>'ok') is distinct from 'true' then
    return jsonb_build_object('ok',false,'error',v_context->>'error','entity','web_order_request');
  end if;
  v_reason:=case when p_decision='rejected' then btrim(p_reason) else null end;
  if p_request_id is null or p_decision_id is null
     or p_decision is null or p_decision not in ('accepted','rejected')
     or (p_decision='rejected' and (v_reason is null or length(v_reason) not between 1 and 240
                                  or v_reason~'[[:cntrl:]]')) then
    return jsonb_build_object('ok',false,'error','invalid_request','entity','web_order_request');
  end if;
  select * into v_request from public.web_order_requests w
    where w.id=p_request_id and w.organization_id=(v_context->>'organization_id')::uuid
      and w.restaurant_id=(v_context->>'restaurant_id')::uuid
      and w.branch_id=(v_context->>'branch_id')::uuid for update;
  if not found then
    return jsonb_build_object('ok',false,'error','not_found','entity','web_order_request');
  end if;
  v_now:=clock_timestamp();
  if (v_context->>'pin_expires_at')::timestamptz<=v_now
     or (v_context->>'session_expires_at')::timestamptz<=v_now then
    return jsonb_build_object('ok',false,'error','invalid_session','entity','web_order_request');
  end if;
  v_payload_hash:=encode(sha256(convert_to(jsonb_build_object(
    'request_id',p_request_id,'decision',p_decision,'reason',v_reason)::text,'UTF8')),'hex');
  select * into v_used from public.web_order_decisions d
    where d.organization_id=v_request.organization_id and d.restaurant_id=v_request.restaurant_id
      and d.branch_id=v_request.branch_id and d.decision_id=p_decision_id;
  if found and (v_used.request_id<>p_request_id or v_used.payload_hash<>v_payload_hash) then
    return jsonb_build_object('ok',false,'error','decision_conflict','entity','web_order_request');
  end if;
  if v_request.status in ('accepted','rejected') then
    select * into v_decision from public.web_order_decisions d where d.request_id=p_request_id;
    if not found or v_decision.decision<>p_decision or v_decision.payload_hash<>v_payload_hash
       or v_decision.canonical_order_id is distinct from v_request.canonical_order_id then
      return jsonb_build_object('ok',false,'error','decision_conflict','entity','web_order_request');
    end if;
    return jsonb_build_object('ok',true,'request_id',p_request_id,'status',v_request.status,
      'canonical_order_id',v_request.canonical_order_id,'decision_id',v_decision.decision_id,
      'replayed',true);
  end if;
  if v_request.status<>'pending' or v_request.expires_at<=v_now then
    return jsonb_build_object('ok',false,'error','request_expired','entity','web_order_request');
  end if;

  if p_decision='accepted' then
    -- The token-proof helper already holds the hierarchy's branch SHARE lock;
    -- tax and kitchen mode cannot change under this acceptance.
    select b.kitchen_workflow_mode into v_mode from public.branches b
      where b.id=v_request.branch_id and b.organization_id=v_request.organization_id
        and b.restaurant_id=v_request.restaurant_id and b.status='active' and b.deleted_at is null
      for share;
    if not found or v_mode not in ('kds','printer_only') then
      return jsonb_build_object('ok',false,'error','ordering_unavailable','entity','web_order_request');
    end if;
    -- Restaurant is already hierarchy-locked before profile (publication parity).
    select * into v_profile from public.restaurant_storefront_profiles p
      where p.organization_id=v_request.organization_id and p.restaurant_id=v_request.restaurant_id
        and p.deleted_at is null for share;
    if not found or v_profile.storefront_branch_id is distinct from v_request.branch_id then
      return jsonb_build_object('ok',false,'error','ordering_unavailable','entity','web_order_request');
    end if;
    select s.id into v_shift_id from public.shifts s
      where s.organization_id=v_request.organization_id and s.restaurant_id=v_request.restaurant_id
        and s.branch_id=v_request.branch_id and s.device_id=p_device_id
        and s.status='open' and s.deleted_at is null for share;
    if not found then
      return jsonb_build_object('ok',false,'error','shift_required','entity','web_order_request');
    end if;
    select array_agg(distinct (e->>'menu_item_id')::uuid) into v_item_ids
      from jsonb_array_elements(v_request.priced_items) e;
    -- The same parent UPDATE locks used by canonical submit / availability set
    -- also block FK KEY SHARE inserts when an override or group is ABSENT.
    perform 1 from public.menu_items i
      where i.organization_id=v_request.organization_id and i.id=any(v_item_ids)
      order by i.id for update;
    perform 1 from public.menu_categories c
      where c.organization_id=v_request.organization_id and c.id in (
        select i.menu_category_id from public.menu_items i
          where i.organization_id=v_request.organization_id and i.id=any(v_item_ids))
      order by c.id for share;
    -- Include inactive/deleted rows: activation, reparenting and prep classifier
    -- peers must not change while pricing and canonical snapshots are built.
    perform 1 from public.modifiers m
      where m.organization_id=v_request.organization_id and m.menu_item_id=any(v_item_ids)
      order by m.id for update;
    select array_agg(m.id) into v_group_ids from public.modifiers m
      where m.organization_id=v_request.organization_id and m.menu_item_id=any(v_item_ids);
    perform 1 from public.modifier_options o
      where o.organization_id=v_request.organization_id and o.modifier_id=any(v_group_ids)
      order by o.id for share;
    perform 1 from public.menu_item_branch_availability a
      where a.organization_id=v_request.organization_id and a.branch_id=v_request.branch_id
        and a.menu_item_id=any(v_item_ids) order by a.id for share;
    -- Sample again AFTER every potentially blocking catalog/shift lock.
    v_now:=clock_timestamp();
    if (v_context->>'pin_expires_at')::timestamptz<=v_now
       or (v_context->>'session_expires_at')::timestamptz<=v_now then
      return jsonb_build_object('ok',false,'error','invalid_session','entity','web_order_request');
    end if;
    if v_request.expires_at<=v_now then
      return jsonb_build_object('ok',false,'error','request_expired','entity','web_order_request');
    end if;
    select jsonb_agg(jsonb_build_object('menu_item_id',e.line->'menu_item_id',
      'quantity',e.line->'quantity','modifiers',coalesce((
        select jsonb_agg(jsonb_build_object('modifier_option_id',m.option->'modifier_option_id',
          'quantity',m.option->'quantity') order by m.ord)
        from jsonb_array_elements(e.line->'modifiers') with ordinality m(option,ord)
      ),'[]'::jsonb)) order by e.ord) into v_items
      from jsonb_array_elements(v_request.priced_items) with ordinality e(line,ord);
    v_quote:=app.price_web_order(v_profile.slug,v_items);
    if (v_quote->>'ok') is distinct from 'true' then
      v_error:=case when v_quote->>'error' in ('item_unavailable','modifier_selection_invalid')
                    then v_quote->>'error' else 'ordering_unavailable' end;
      return jsonb_build_object('ok',false,'error',v_error,'entity','web_order_request');
    end if;
    if v_quote->>'organization_id' is distinct from v_request.organization_id::text
       or v_quote->>'restaurant_id' is distinct from v_request.restaurant_id::text
       or v_quote->>'branch_id' is distinct from v_request.branch_id::text then
      return jsonb_build_object('ok',false,'error','ordering_unavailable','entity','web_order_request');
    end if;
    if v_quote->'priced_items' is distinct from v_request.priced_items
       or v_quote->>'currency_code' is distinct from v_request.currency_code
       or (v_quote->>'subtotal_minor')::bigint is distinct from v_request.subtotal_minor
       or (v_quote->>'tax_total_minor')::bigint is distinct from v_request.tax_total_minor
       or (v_quote->>'grand_total_minor')::bigint is distinct from v_request.grand_total_minor then
      return jsonb_build_object('ok',false,'error','quote_changed','entity','web_order_request');
    end if;
    for v_item in select value from jsonb_array_elements(v_request.priced_items) loop
      v_modifiers:='[]'::jsonb;
      for v_modifier in select value from jsonb_array_elements(v_item->'modifiers') loop
        select m.name into v_group_name from public.modifiers m
          where m.organization_id=v_request.organization_id
            and m.id=(v_modifier->>'modifier_id')::uuid;
        v_modifiers:=v_modifiers||jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
          'modifier_option_id',v_modifier->'modifier_option_id',
          'modifier_name_snapshot',v_group_name,'option_name_snapshot',v_modifier->'option_name_snapshot',
          'quantity',v_modifier->'quantity','price_minor_snapshot',v_modifier->'price_minor_snapshot',
          'meat_snapshot',app.trusted_modifier_prep_snapshot(v_request.organization_id,
            (v_item->>'menu_item_id')::uuid,(v_modifier->>'modifier_option_id')::uuid,
            v_item->'modifiers'))));
      end loop;
      -- Canonical submit reads optional snapshots with ->, so an absent value
      -- must be OMITTED (SQL NULL), never represented by JSON null: the existing
      -- order_items_prep_snapshot_shape CHECK permits only arrays or SQL NULL.
      v_canonical_items:=v_canonical_items||jsonb_build_array(jsonb_strip_nulls(jsonb_build_object(
        'menu_item_id',v_item->'menu_item_id','menu_item_name_snapshot',v_item->'item_name_snapshot',
        'quantity',v_item->'quantity','unit_price_minor_snapshot',v_item->'unit_price_minor_snapshot',
        'line_discount_minor',0,'modifiers',v_modifiers,
        'prep_snapshot',app.trusted_item_prep_snapshot(v_request.organization_id,
          (v_item->>'menu_item_id')::uuid,v_item->'modifiers'))));
    end loop;
    v_order_id:=gen_random_uuid();
    v_operation_id:='web-accept:'||p_request_id::text||':'||p_decision_id::text;
    v_payload:=jsonb_build_object('order_id',v_order_id,'order_type','takeaway',
      'table_id',null,'shift_id',v_shift_id,'currency_code',v_request.currency_code,
      'notes',v_request.notes,'order_items',v_canonical_items,
      'subtotal_minor',v_request.subtotal_minor,'discount_total_minor',0,
      'tax_total_minor',v_request.tax_total_minor,'grand_total_minor',v_request.grand_total_minor,
      'customer_name',v_request.customer_name,'customer_phone',v_request.customer_phone,
      'dispatch_mode',case when v_mode='printer_only' then 'direct_print' else 'kds' end);
  end if;

  -- ONE subtransaction covers sync ledger, canonical writes/audit/dispatch,
  -- immutable request mapping, final deadlines and the attributed decision.
  -- Existing sync_push catches inner faults: its outer ok alone is NOT proof.
  begin
    if p_decision='accepted' then
      v_sync:=app.sync_push(p_pin_session_id,p_device_id,jsonb_build_array(jsonb_build_object(
        'local_operation_id',v_operation_id,'operation_type','order.submit',
        'target_entity','order','target_id',v_order_id,'payload',v_payload,
        'depends_on',jsonb_build_array(),'client_created_at',clock_timestamp())));
      if (v_sync->>'ok') is distinct from 'true'
         or jsonb_typeof(v_sync->'results') is distinct from 'array' then
        raise exception using errcode='RW001',message='order_rejected';
      end if;
      if jsonb_array_length(v_sync->'results')<>1 then
        raise exception using errcode='RW001',message='order_rejected';
      end if;
      v_result:=v_sync->'results'->0;
      if (v_result->>'ok') is distinct from 'true'
         or v_result->>'status' is distinct from 'applied'
         or v_result->>'local_operation_id' is distinct from v_operation_id
         or v_result->>'operation_type' is distinct from 'order.submit'
         or v_result->>'order_id' is distinct from v_order_id::text then
        -- Preserve whole-transaction retry semantics even when sync_push's
        -- internal exception handler has converted a concurrency error.
        if v_result->>'sqlstate' in ('40P01','40001') then
          raise exception using errcode=v_result->>'sqlstate',message='retry web order decision';
        end if;
        raise exception using errcode='RW001',message='order_rejected';
      end if;
      if not exists (select 1 from public.orders o where o.id=v_order_id
        and o.organization_id=v_request.organization_id and o.restaurant_id=v_request.restaurant_id
        and o.branch_id=v_request.branch_id and o.device_id=p_device_id
        and o.pin_session_id=p_pin_session_id and o.shift_id=v_shift_id
        and o.order_type='takeaway' and o.local_operation_id=v_operation_id and o.deleted_at is null) then
        raise exception using errcode='RW001',message='order_rejected';
      end if;
    end if;
    v_now:=clock_timestamp();
    if (v_context->>'pin_expires_at')::timestamptz<=v_now
       or (v_context->>'session_expires_at')::timestamptz<=v_now then
      raise exception using errcode='RW002',message='invalid_session';
    end if;
    if v_request.expires_at<=v_now then
      raise exception using errcode='RW003',message='request_expired';
    end if;
    update public.web_order_requests set status=p_decision,canonical_order_id=v_order_id,
      rejection_reason=v_reason,decided_at=v_now where id=p_request_id
        and organization_id=v_request.organization_id and restaurant_id=v_request.restaurant_id
        and branch_id=v_request.branch_id and status='pending';
    if not found then raise exception using errcode='RW001',message='order_rejected'; end if;
    insert into public.web_order_decisions(organization_id,restaurant_id,branch_id,request_id,
      decision_id,decision,payload_hash,device_id,pin_session_id,employee_profile_id,
      resolved_membership_id,shift_id,canonical_order_id,decided_at)
    values(v_request.organization_id,v_request.restaurant_id,v_request.branch_id,p_request_id,
      p_decision_id,p_decision,v_payload_hash,p_device_id,p_pin_session_id,
      (v_context->>'employee_profile_id')::uuid,(v_context->>'resolved_membership_id')::uuid,
      v_shift_id,v_order_id,v_now);
    -- Include any time spent in mapping/audit triggers in the final deadline.
    if v_request.expires_at<=clock_timestamp() then
      raise exception using errcode='RW003',message='request_expired';
    end if;
    if (v_context->>'pin_expires_at')::timestamptz<=clock_timestamp()
       or (v_context->>'session_expires_at')::timestamptz<=clock_timestamp() then
      raise exception using errcode='RW002',message='invalid_session';
    end if;
  exception
    when sqlstate 'RW001' then
      return jsonb_build_object('ok',false,'error','order_rejected','entity','web_order_request');
    when sqlstate 'RW002' then
      return jsonb_build_object('ok',false,'error','invalid_session','entity','web_order_request');
    when sqlstate 'RW003' then
      return jsonb_build_object('ok',false,'error','request_expired','entity','web_order_request');
    when unique_violation then
      -- A decision UUID raced on another request. The subtransaction rollback
      -- removes ALL canonical effects before returning this safe conflict.
      get stacked diagnostics v_constraint = constraint_name;
      if v_constraint='web_order_decisions_identity_key' then
        return jsonb_build_object('ok',false,'error','decision_conflict','entity','web_order_request');
      end if;
      raise;
    when insufficient_privilege then
      -- The existing guard samples clock_timestamp itself; the deadline can
      -- cross between our precheck and its UPDATE trigger. Other faults escape.
      if sqlerrm='web order request expired' then
        return jsonb_build_object('ok',false,'error','request_expired','entity','web_order_request');
      end if;
      raise;
  end;
  return jsonb_build_object('ok',true,'request_id',p_request_id,'status',p_decision,
    'canonical_order_id',v_order_id,'decision_id',p_decision_id,'replayed',false);
end;
$$;
revoke all on function app.decide_pos_web_order(uuid,uuid,text,uuid,uuid,text,text)
  from public,anon,authenticated,service_role;

create function app.pos_accept_web_order(
  p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,
  p_request_id uuid,p_decision_id uuid
) returns jsonb language sql volatile security definer set search_path = '' as $$
  select app.decide_pos_web_order(p_pin_session_id,p_device_id,p_device_session_token,
    p_request_id,p_decision_id,'accepted',null);
$$;
create function app.pos_reject_web_order(
  p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,
  p_request_id uuid,p_decision_id uuid,p_reason text
) returns jsonb language sql volatile security definer set search_path = '' as $$
  select app.decide_pos_web_order(p_pin_session_id,p_device_id,p_device_session_token,
    p_request_id,p_decision_id,'rejected',p_reason);
$$;
create function public.pos_web_order_inbox(
  p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,
  p_request_id uuid default null,p_before_created_at timestamptz default null,
  p_before_id uuid default null,p_limit integer default 50
) returns jsonb language sql volatile security invoker set search_path = '' as $$
  select app.pos_web_order_inbox(p_pin_session_id,p_device_id,p_device_session_token,
    p_request_id,p_before_created_at,p_before_id,p_limit);
$$;
create function public.pos_accept_web_order(
  p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,
  p_request_id uuid,p_decision_id uuid
) returns jsonb language sql volatile security invoker set search_path = '' as $$
  select app.pos_accept_web_order(p_pin_session_id,p_device_id,p_device_session_token,
    p_request_id,p_decision_id);
$$;
create function public.pos_reject_web_order(
  p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,
  p_request_id uuid,p_decision_id uuid,p_reason text
) returns jsonb language sql volatile security invoker set search_path = '' as $$
  select app.pos_reject_web_order(p_pin_session_id,p_device_id,p_device_session_token,
    p_request_id,p_decision_id,p_reason);
$$;
revoke all on function
  app.pos_web_order_inbox(uuid,uuid,text,uuid,timestamptz,uuid,integer),
  app.pos_accept_web_order(uuid,uuid,text,uuid,uuid),
  app.pos_reject_web_order(uuid,uuid,text,uuid,uuid,text),
  public.pos_web_order_inbox(uuid,uuid,text,uuid,timestamptz,uuid,integer),
  public.pos_accept_web_order(uuid,uuid,text,uuid,uuid),
  public.pos_reject_web_order(uuid,uuid,text,uuid,uuid,text)
  from public,anon,authenticated,service_role;
grant execute on function
  app.pos_web_order_inbox(uuid,uuid,text,uuid,timestamptz,uuid,integer),
  app.pos_accept_web_order(uuid,uuid,text,uuid,uuid),
  app.pos_reject_web_order(uuid,uuid,text,uuid,uuid,text),
  public.pos_web_order_inbox(uuid,uuid,text,uuid,timestamptz,uuid,integer),
  public.pos_accept_web_order(uuid,uuid,text,uuid,uuid),
  public.pos_reject_web_order(uuid,uuid,text,uuid,uuid,text)
  to authenticated;
alter function app.pos_web_order_context(uuid,uuid,text) owner to postgres;
alter function app.pos_web_order_inbox(uuid,uuid,text,uuid,timestamptz,uuid,integer) owner to postgres;
alter function app.decide_pos_web_order(uuid,uuid,text,uuid,uuid,text,text) owner to postgres;
alter function app.pos_accept_web_order(uuid,uuid,text,uuid,uuid) owner to postgres;
alter function app.pos_reject_web_order(uuid,uuid,text,uuid,uuid,text) owner to postgres;

commit;
