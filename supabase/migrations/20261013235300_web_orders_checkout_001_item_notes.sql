-- WEB-ORDERS-CHECKOUT-001 / D-047: optional per-line customer notes.
-- Additive only. No channel, deployment, canonical writer or printer changes.
begin;

-- Keep absent/empty notes absent: pre-existing frozen quotes and payload hashes
-- retain their exact note-free shape. Character length counts Unicode scalars
-- in UTF8 PostgreSQL; JSON input rejects unpaired surrogates before this helper.
create function app.normalize_web_order_item_notes(p_items jsonb) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
  v_line jsonb; v_notes text; v_items jsonb:='[]'::jsonb;
  -- ECMAScript String.trim whitespace (controls other than LF are rejected).
  v_trim text:=U&'\0020\00a0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200a\2028\2029\202f\205f\3000\feff' || E'\n';
begin
  if jsonb_typeof(p_items) is distinct from 'array' then
    return jsonb_build_object('ok',false,'error','invalid_request');
  end if;
  if jsonb_array_length(p_items) not between 1 and 20 then
    return jsonb_build_object('ok',false,'error','invalid_request');
  end if;
  for v_line in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(v_line) is distinct from 'object' then
      return jsonb_build_object('ok',false,'error','invalid_request');
    end if;
    if v_line ? 'notes' then
      if jsonb_typeof(v_line->'notes') is distinct from 'string' then
        return jsonb_build_object('ok',false,'error','invalid_request');
      end if;
      v_notes:=v_line->>'notes';
      -- Reject raw oversize input, never truncate even whitespace. LF is the
      -- only accepted control; explicit ranges also cover C1 in C locales.
      if length(v_notes)>140 or replace(v_notes,E'\n','')~'[[:cntrl:]]'
         or v_notes~U&'[\007f-\009f]' then
        return jsonb_build_object('ok',false,'error','invalid_request');
      end if;
      v_notes:=btrim(v_notes,v_trim);
      v_line:=v_line-'notes';
      if v_notes<>'' then v_line:=v_line||jsonb_build_object('notes',v_notes); end if;
    end if;
    v_items:=v_items||jsonb_build_array(v_line);
  end loop;
  return jsonb_build_object('ok',true,'items',v_items);
end;
$$;
revoke all on function app.normalize_web_order_item_notes(jsonb)
  from public,anon,authenticated,service_role;

create or replace function app.price_web_order(p_slug text,p_items jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_profile public.restaurant_storefront_profiles;
  v_menu jsonb; v_line jsonb; v_item jsonb; v_mod jsonb; v_option jsonb;
  v_group record; v_options jsonb; v_lines jsonb := '[]'; v_id uuid; v_option_id uuid;
  v_seen uuid[]; v_qty bigint; v_opt_qty bigint; v_unit bigint; v_delta bigint;
  v_mod_sum bigint; v_line_total bigint; v_subtotal bigint:=0; v_tax bigint; v_total_units integer:=0;
  v_normalized jsonb;
  v_count integer; v_min integer; v_max integer; v_group_qty bigint;
begin
  v_normalized:=app.normalize_web_order_item_notes(p_items);
  if (v_normalized->>'ok') is distinct from 'true' then return v_normalized; end if;
  p_items:=v_normalized->'items';
  if jsonb_typeof(p_items) is distinct from 'array' then
    return jsonb_build_object('ok',false,'error','invalid_request');
  end if;
  if jsonb_array_length(p_items) not between 1 and 20 then
    return jsonb_build_object('ok',false,'error','invalid_request');
  end if;
  select * into v_profile from public.restaurant_storefront_profiles
    where slug=p_slug and deleted_at is null;
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
  v_menu:=public.storefront_menu(p_slug);
  if (v_menu->>'ok') is distinct from 'true' then
    return jsonb_build_object('ok',false,'error','not_found');
  end if;
  if (v_menu#>>'{service,state}') is distinct from 'open'
     or not v_profile.pickup_enabled then
    return jsonb_build_object('ok',false,'error','ordering_unavailable');
  end if;
  for v_line in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(v_line) is distinct from 'object' then
      return jsonb_build_object('ok',false,'error','invalid_request');
    end if;
    if not (v_line ?& array['menu_item_id','quantity','modifiers'])
       or exists(select 1 from jsonb_object_keys(v_line) k
                 where k not in ('menu_item_id','quantity','modifiers','notes'))
       or jsonb_typeof(v_line->'menu_item_id') is distinct from 'string'
       or (v_line->>'menu_item_id') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
       or jsonb_typeof(v_line->'quantity') is distinct from 'number'
       or (v_line->>'quantity') !~ '^[0-9]{1,2}$'
       or jsonb_typeof(v_line->'modifiers') is distinct from 'array' then
      return jsonb_build_object('ok',false,'error','invalid_request');
    end if;
    v_id:=(v_line->>'menu_item_id')::uuid; v_qty:=(v_line->>'quantity')::bigint;
    if v_qty not between 1 and 20 or jsonb_array_length(v_line->'modifiers')>20 then
      return jsonb_build_object('ok',false,'error','invalid_request');
    end if;
    v_total_units:=v_total_units+v_qty;
    if v_total_units>50 then return jsonb_build_object('ok',false,'error','invalid_request'); end if;
    select value into v_item from jsonb_array_elements(v_menu->'items')
      where value->>'id'=v_id::text;
    if not found or (v_item->>'availability') is distinct from 'available' then
      return jsonb_build_object('ok',false,'error','item_unavailable');
    end if;
    v_unit:=(v_item->>'base_price_minor')::bigint;
    if v_unit not between 0 and 10000000 then
      return jsonb_build_object('ok',false,'error','menu_unavailable');
    end if;
    v_options:='[]'; v_seen:=array[]::uuid[]; v_mod_sum:=0;
    for v_mod in select value from jsonb_array_elements(v_line->'modifiers') loop
      if jsonb_typeof(v_mod) is distinct from 'object' then
        return jsonb_build_object('ok',false,'error','invalid_request');
      end if;
      if not (v_mod ?& array['modifier_option_id','quantity'])
         or exists(select 1 from jsonb_object_keys(v_mod) k
                   where k not in ('modifier_option_id','quantity'))
         or jsonb_typeof(v_mod->'modifier_option_id') is distinct from 'string'
         or (v_mod->>'modifier_option_id') !~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
         or jsonb_typeof(v_mod->'quantity') is distinct from 'number'
         or (v_mod->>'quantity') !~ '^[0-9]{1,2}$' then
        return jsonb_build_object('ok',false,'error','invalid_request');
      end if;
      v_option_id:=(v_mod->>'modifier_option_id')::uuid;
      v_opt_qty:=(v_mod->>'quantity')::bigint;
      if v_option_id=any(v_seen) or v_opt_qty not between 1 and 20 then
        return jsonb_build_object('ok',false,'error','invalid_request');
      end if;
      v_seen:=array_append(v_seen,v_option_id);
      select opt.value into v_option from jsonb_array_elements(v_menu->'modifier_options') opt
        join jsonb_array_elements(v_menu->'modifiers') grp
          on grp.value->>'id'=opt.value->>'modifier_id'
        where opt.value->>'id'=v_option_id::text and grp.value->>'item_id'=v_id::text;
      if not found then return jsonb_build_object('ok',false,'error','modifier_selection_invalid'); end if;
      v_delta:=(v_option->>'price_delta_minor')::bigint;
      if v_delta not between 0 and 10000000 then
        return jsonb_build_object('ok',false,'error','menu_unavailable');
      end if;
      v_mod_sum:=v_mod_sum+v_delta*v_opt_qty;
      v_options:=v_options||jsonb_build_array(jsonb_build_object(
        'modifier_option_id',v_option_id,'modifier_id',v_option->>'modifier_id',
        'option_name_snapshot',v_option->>'name','quantity',v_opt_qty,
        'price_minor_snapshot',v_delta));
    end loop;
    for v_group in
      select m.* from public.modifiers m where m.organization_id=v_profile.organization_id
        and m.restaurant_id=v_profile.restaurant_id and m.menu_item_id=v_id
        and m.is_active and m.deleted_at is null
        and (m.branch_id is null or m.branch_id=v_profile.storefront_branch_id)
    loop
      v_min:=case when v_group.selection_type='single' then 1
                  when v_group.is_required then greatest(1,v_group.min_select)
                  else v_group.min_select end;
      v_max:=case when v_group.selection_type='single' then 1 else v_group.max_select end;
      select count(*) into v_count from jsonb_array_elements(v_options) o
        where o->>'modifier_id'=v_group.id::text;
      if v_min<0 or (v_max is not null and v_min>v_max)
         or v_count<v_min or (v_max is not null and v_count>v_max) then
        return jsonb_build_object('ok',false,'error','modifier_selection_invalid');
      end if;
      for v_group_qty in select (o->>'quantity')::bigint from jsonb_array_elements(v_options) o
        where o->>'modifier_id'=v_group.id::text
      loop
        if (not v_group.allow_quantity and v_group_qty<>1)
           or (v_group.allow_quantity and v_group.max_quantity is not null
               and v_group_qty>v_group.max_quantity) then
          return jsonb_build_object('ok',false,'error','modifier_selection_invalid');
        end if;
      end loop;
    end loop;
    v_line_total:=v_qty*(v_unit+v_mod_sum);
    v_subtotal:=v_subtotal+v_line_total;
    if v_subtotal>10000000 then return jsonb_build_object('ok',false,'error','menu_unavailable'); end if;
    v_lines:=v_lines||jsonb_build_array(jsonb_build_object('menu_item_id',v_id,
      'item_name_snapshot',v_item->>'name','quantity',v_qty,'unit_price_minor_snapshot',v_unit,
      'modifiers',v_options,'line_total_minor',v_line_total)
      ||case when v_line ? 'notes' then jsonb_build_object('notes',v_line->'notes') else '{}'::jsonb end);
  end loop;
  v_tax:=app.edit_tax_minor(v_subtotal,(v_menu#>>'{tax,enabled}')::boolean,
    (v_menu#>>'{tax,rate_bp}')::integer,v_menu#>>'{tax,mode}');
  if v_tax is null or v_subtotal+v_tax>10000000 then
    return jsonb_build_object('ok',false,'error','menu_unavailable');
  end if;
  return jsonb_build_object('ok',true,'organization_id',v_profile.organization_id,
    'restaurant_id',v_profile.restaurant_id,'branch_id',v_profile.storefront_branch_id,
    'priced_items',v_lines,'currency_code','ILS','subtotal_minor',v_subtotal,
    'tax_total_minor',v_tax,'grand_total_minor',v_subtotal+v_tax);
exception when invalid_text_representation or numeric_value_out_of_range then
  return jsonb_build_object('ok',false,'error','invalid_request');
end;
$$;

create or replace function app.submit_web_order_request(
  p_slug text,p_client_request_id uuid,p_status_token_hash text,p_order jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_profile public.restaurant_storefront_profiles;
  v_channel public.web_order_channel_settings;
  v_request public.web_order_requests;
  v_now timestamptz:=clock_timestamp(); v_day date; v_payload_hash text;
  v_normalized jsonb;
  v_quote jsonb; v_customer jsonb; v_existing boolean; v_branch uuid; v_public_menu jsonb;
begin
  if p_slug is null or length(p_slug) not between 3 and 48
     or p_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or p_client_request_id is null
     or p_client_request_id::text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     or p_status_token_hash is null or p_status_token_hash !~ '^[0-9a-f]{64}$'
     or jsonb_typeof(p_order) is distinct from 'object' then
    return jsonb_build_object('ok',false,'error','invalid_request');
  end if;
  if not (p_order ?& array['order_type','customer','items','notes'])
     or exists(select 1 from jsonb_object_keys(p_order) k
               where k not in ('order_type','customer','items','notes'))
     or (p_order->>'order_type') is distinct from 'takeaway'
     or jsonb_typeof(p_order->'customer') is distinct from 'object'
     or jsonb_typeof(p_order->'notes') is distinct from 'string'
     or length(p_order->>'notes')>500 or replace(p_order->>'notes',E'\n','')~'[[:cntrl:]]'
     or octet_length(p_order::text)>32768 then
    return jsonb_build_object('ok',false,'error','invalid_request');
  end if;
  v_normalized:=app.normalize_web_order_item_notes(p_order->'items');
  if (v_normalized->>'ok') is distinct from 'true' then return v_normalized; end if;
  p_order:=jsonb_set(p_order,'{items}',v_normalized->'items');
  v_customer:=p_order->'customer';
  if not (v_customer ?& array['name','phone'])
     or exists(select 1 from jsonb_object_keys(v_customer) k where k not in ('name','phone'))
     or jsonb_typeof(v_customer->'name') is distinct from 'string'
     or jsonb_typeof(v_customer->'phone') is distinct from 'string'
     or length(btrim(v_customer->>'name')) not between 1 and 80
     or (v_customer->>'name')~'[[:cntrl:]]'
     or (v_customer->>'phone') !~ '^\+[1-9][0-9]{7,14}$' then
    return jsonb_build_object('ok',false,'error','invalid_request');
  end if;
  select * into v_profile from public.restaurant_storefront_profiles
    where slug=p_slug and deleted_at is null;
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
  -- Shared ordering of locks: identity, then branch. The UNIQUE key is a backstop.
  perform pg_advisory_xact_lock(hashtextextended(v_profile.restaurant_id::text||':'||p_client_request_id::text,0));
  v_payload_hash:=encode(sha256(convert_to(p_order::text,'UTF8')),'hex');
  select * into v_request from public.web_order_requests
    where restaurant_id=v_profile.restaurant_id and client_request_id=p_client_request_id;
  v_existing:=found;
  -- Do not reveal a private/unpublished slug through channel or quota errors.
  -- Original capability replays remain recoverable after unpublishing.
  if not v_existing then
    v_public_menu:=public.storefront_menu(p_slug);
    if (v_public_menu->>'ok') is distinct from 'true' then
      return jsonb_build_object('ok',false,'error','not_found');
    end if;
  end if;
  v_branch:=case when v_existing then v_request.branch_id else v_profile.storefront_branch_id end;
  select * into v_channel from public.web_order_channel_settings
    where organization_id=v_profile.organization_id and restaurant_id=v_profile.restaurant_id
      and branch_id=v_branch for update;
  if not found then
    return jsonb_build_object('ok',false,'error','ordering_unavailable');
  end if;
  -- Clock is sampled AFTER waiting for the channel lock: expiry/quotas cannot
  -- be backdated by a slow concurrent request.
  v_now:=clock_timestamp(); v_day:=(v_now at time zone 'UTC')::date;
  if v_channel.submit_window_started_at<=v_now-interval '1 minute' then
    v_channel.submit_window_started_at:=v_now;
    v_channel.submit_attempt_count:=0; v_channel.submitted_in_window:=0;
  end if;
  if v_channel.submit_day<>v_day then v_channel.submit_day:=v_day; v_channel.submitted_today:=0; end if;
  if v_channel.submit_attempt_count>=60 then
    return jsonb_build_object('ok',false,'error','rate_limited');
  end if;
  update public.web_order_channel_settings set
    submit_window_started_at=v_channel.submit_window_started_at,
    submit_attempt_count=v_channel.submit_attempt_count+1,
    submitted_in_window=v_channel.submitted_in_window,
    submit_day=v_channel.submit_day,submitted_today=v_channel.submitted_today,updated_at=v_now
    where branch_id=v_channel.branch_id;
  -- Replays use the original branch and quote, even after a channel is paused.
  -- They consume the attempt budget, but never the new-request quota/capacity.
  if v_existing then
    if v_request.status_token_hash<>p_status_token_hash or v_request.payload_hash<>v_payload_hash then
      return jsonb_build_object('ok',false,'error','idempotency_conflict');
    end if;
    if v_request.status_until<=v_now then return jsonb_build_object('ok',false,'error','not_found'); end if;
    return app.web_order_public_result(v_request,true);
  end if;
  if not v_channel.submission_enabled then
    return jsonb_build_object('ok',false,'error','ordering_unavailable');
  end if;
  if v_channel.submitted_in_window>=10 or v_channel.submitted_today>=1000 then
    return jsonb_build_object('ok',false,'error','rate_limited');
  end if;
  if (select count(*) from public.web_order_requests where branch_id=v_channel.branch_id
        and status='pending' and expires_at>v_now)>=50
     or (select count(*) from public.web_order_requests where branch_id=v_channel.branch_id
        and customer_phone=v_customer->>'phone' and status='pending' and expires_at>v_now)>=3 then
    return jsonb_build_object('ok',false,'error','capacity_reached');
  end if;
  v_quote:=app.price_web_order(p_slug,p_order->'items');
  if (v_quote->>'ok') is distinct from 'true' then return v_quote; end if;
  if v_quote->>'organization_id'<>v_channel.organization_id::text
     or v_quote->>'restaurant_id'<>v_channel.restaurant_id::text
     or v_quote->>'branch_id'<>v_channel.branch_id::text then
    return jsonb_build_object('ok',false,'error','ordering_unavailable');
  end if;
  insert into public.web_order_requests (
    organization_id,restaurant_id,branch_id,client_request_id,status_token_hash,payload_hash,
    customer_name,customer_phone,notes,priced_items,currency_code,
    subtotal_minor,tax_total_minor,grand_total_minor,created_at,expires_at,status_until
  ) values (
    v_channel.organization_id,v_channel.restaurant_id,v_channel.branch_id,p_client_request_id,
    p_status_token_hash,v_payload_hash,btrim(v_customer->>'name'),v_customer->>'phone',p_order->>'notes',
    v_quote->'priced_items',v_quote->>'currency_code',(v_quote->>'subtotal_minor')::bigint,
    (v_quote->>'tax_total_minor')::bigint,(v_quote->>'grand_total_minor')::bigint,
    v_now,v_now+interval '15 minutes',v_now+interval '24 hours'
  ) returning * into v_request;
  insert into public.web_order_request_events(organization_id,restaurant_id,branch_id,request_id,event_type)
    values(v_request.organization_id,v_request.restaurant_id,v_request.branch_id,v_request.id,'received');
  update public.web_order_channel_settings set submitted_in_window=submitted_in_window+1,
    submitted_today=submitted_today+1 where branch_id=v_channel.branch_id;
  return app.web_order_public_result(v_request,false);
end;
$$;

create or replace function app.decide_pos_web_order(
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
      ),'[]'::jsonb))
      ||case when e.line ? 'notes' then jsonb_build_object('notes',e.line->'notes') else '{}'::jsonb end
      order by e.ord) into v_items
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
        'line_discount_minor',0,'modifiers',v_modifiers,'notes',v_item->>'notes',
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

create or replace function public.storefront_menu(p_slug text)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  c_not_found   constant jsonb := jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'storefront_menu');
  c_media_base  constant text  := '/storage/v1/object/public/storefront-media/';
  c_cap_cat     constant integer := 100;
  c_cap_item    constant integer := 500;
  c_cap_mod     constant integer := 2000;
  c_cap_opt     constant integer := 8000;
  v_now         timestamptz := now();
  v_p           record;
  v_hours       record;
  v_state       text;
  v_categories  jsonb;
  v_items       jsonb;
  v_modifiers   jsonb;
  v_options     jsonb;
  v_logo        text;
  v_hero        text;
  v_max_updated timestamptz;
  v_menu_version text;
begin
  -- (a) request grammar (the UI trust boundary); anything else is not_found
  if p_slug is null or p_slug !~ '^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$' then
    return c_not_found;
  end if;

  -- (b) resolve the published profile + the live ancestry (P0), scope derived
  --     ONCE here; no id ever leaves this function
  select p.restaurant_id, p.organization_id, p.storefront_branch_id, p.slug, p.display_name, p.tagline,
         p.public_city, p.public_address, p.public_phone, p.primary_color, p.accent_color, p.visual_preset,
         p.locale_default, p.card_mode, p.motion, p.pickup_enabled, p.paused_until, p.opening_hours,
         p.logo_media_id, p.hero_media_id, p.is_published, p.version, p.updated_at,
         o.status as o_status, o.deleted_at as o_deleted,
         r.status as r_status, r.deleted_at as r_deleted,
         b.status as b_status, b.deleted_at as b_deleted,
         coalesce(b.timezone, r.timezone) as tz,
         coalesce(r.currency_override, o.default_currency) as currency,
         b.tax_enabled, b.tax_rate_bp, b.tax_mode
    into v_p
    from public.restaurant_storefront_profiles p
    join public.restaurants   r on r.id = p.restaurant_id and r.organization_id = p.organization_id
    join public.organizations o on o.id = p.organization_id
    join public.branches      b on b.id = p.storefront_branch_id
                               and b.organization_id = p.organization_id
                               and b.restaurant_id = p.restaurant_id
   where p.slug = p_slug
     and p.deleted_at is null;
  if not found then
    return c_not_found;
  end if;
  if not v_p.is_published
     or v_p.o_status <> 'active' or v_p.o_deleted is not null
     or v_p.r_status <> 'active' or v_p.r_deleted is not null
     or v_p.b_status <> 'active' or v_p.b_deleted is not null
     or v_p.tz is null
     or v_p.currency is distinct from 'ILS'
     or (v_p.tax_enabled and v_p.tax_mode <> 'exclusive') then
    return c_not_found;
  end if;

  -- (c) hours in the branch timezone; an unresolvable zone is a P0 failure
  begin
    select * into v_hours from app.storefront_service_window(v_p.opening_hours, v_p.tz, v_now);
  exception when invalid_parameter_value or invalid_datetime_format then
    return c_not_found;
  end;
  v_state := case
               when v_p.paused_until is not null and v_p.paused_until > v_now then 'paused'
               when v_hours.open_now then 'open'
               else 'closed'
             end;

  -- (d) published media only; never the private key, never a UUID
  select c_media_base || sm.object_key into v_logo
    from public.storefront_media sm
   where sm.id = v_p.logo_media_id and sm.organization_id = v_p.organization_id and sm.restaurant_id = v_p.restaurant_id
     and sm.published_at is not null and sm.unpublished_at is null;
  select c_media_base || sm.object_key into v_hero
    from public.storefront_media sm
   where sm.id = v_p.hero_media_id and sm.organization_id = v_p.organization_id and sm.restaurant_id = v_p.restaurant_id
     and sm.published_at is not null and sm.unpublished_at is null;

  -- (e) live categories of the restaurant, branch-visible (kiosk_menu (d) VERBATIM)
  select coalesce(jsonb_agg(
           jsonb_build_object('id', c.id, 'name', left(c.name, 80), 'display_order', c.display_order,
                              'icon_key', c.icon_key)
           order by c.display_order, c.name), '[]'::jsonb),
         max(c.updated_at)
    into v_categories, v_max_updated
    from public.menu_categories c
   where c.organization_id = v_p.organization_id
     and c.restaurant_id = v_p.restaurant_id
     and c.is_active
     and c.deleted_at is null
     and (c.branch_id is null or c.branch_id = v_p.storefront_branch_id);

  -- (f) live items with the pos_menu / kiosk_menu (e) predicates VERBATIM;
  --     customer-narrow keys; sold-out from the branch availability override;
  --     image_url only from a PUBLISHED derivative of the item's private key
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', i.id, 'category_id', i.menu_category_id, 'name', left(i.name, 120),
             'description', left(coalesce(i.description, ''), 600),
             'base_price_minor', i.base_price_minor, 'display_order', i.display_order,
             -- vocabulary-filtered AND de-duplicated (so at most four values can ever be served),
             -- keeping the tenant's first-occurrence order
             'tags', coalesce((select jsonb_agg(d.t order by d.ord)
                                 from (select x.t, min(x.ord) as ord
                                         from jsonb_array_elements_text(coalesce(i.tags, '[]'::jsonb)) with ordinality as x(t, ord)
                                        where x.t in ('spicy', 'vegetarian', 'popular', 'new')
                                        group by x.t) d), '[]'::jsonb),
             'image_url', case when sm.object_key is null then null else c_media_base || sm.object_key end,
             'availability', coalesce(a.availability, 'available'))
           order by i.display_order, i.name), '[]'::jsonb),
         greatest(v_max_updated, max(i.updated_at))
    into v_items, v_max_updated
    from public.menu_items i
    join public.menu_categories c
      on c.organization_id = i.organization_id
     and c.restaurant_id   = v_p.restaurant_id
     and c.id = i.menu_category_id
    left join public.menu_item_branch_availability a
      on a.organization_id = i.organization_id
     and a.branch_id       = v_p.storefront_branch_id
     and a.menu_item_id    = i.id
    left join public.storefront_media sm
      on sm.organization_id = i.organization_id
     and sm.restaurant_id   = v_p.restaurant_id
     and sm.source_bucket   = 'menu-images'
     and sm.source_key      = i.image_path
     and sm.variant         = 'w480'
     and exists (select 1 from app.menu_image_scope(sm.source_key) item_source
                  where item_source.menu_item_id = i.id
                    and item_source.branch_id is not distinct from i.branch_id)
     and sm.item_source_snapshot = app.storefront_item_source_snapshot(
           i.organization_id, i.restaurant_id, i.image_path)
     and exists (select 1 from storage.objects derivative
                  where derivative.bucket_id = 'storefront-media' and derivative.name = sm.object_key
                    and derivative.metadata ->> 'mimetype' = 'image/webp'
                    and derivative.metadata ->> 'size' = sm.bytes::text)
     and sm.published_at is not null
     and sm.unpublished_at is null
   where i.organization_id = v_p.organization_id
     and i.restaurant_id = v_p.restaurant_id
     and i.is_active
     and i.deleted_at is null
     and (i.branch_id is null or i.branch_id = v_p.storefront_branch_id)
     and c.is_active
     and c.deleted_at is null
     and (c.branch_id is null or c.branch_id = v_p.storefront_branch_id);

  -- (g) live modifiers of LIVE items (same live visibility predicates; public quantity constraints)
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', m.id, 'item_id', m.menu_item_id, 'name', left(m.name, 80),
             'selection_type', m.selection_type, 'min_select', m.min_select,
             'max_select', m.max_select, 'is_required', m.is_required,
             'allow_quantity', m.allow_quantity, 'max_quantity', m.max_quantity,
             'display_order', m.display_order)
           order by m.display_order, m.name), '[]'::jsonb),
         greatest(v_max_updated, max(m.updated_at))
    into v_modifiers, v_max_updated
    from public.modifiers m
    join public.menu_items i
      on i.organization_id = m.organization_id
     and i.restaurant_id   = v_p.restaurant_id
     and i.id = m.menu_item_id
    join public.menu_categories c
      on c.organization_id = i.organization_id
     and c.restaurant_id   = v_p.restaurant_id
     and c.id = i.menu_category_id
   where m.organization_id = v_p.organization_id
     and m.restaurant_id = v_p.restaurant_id
     and m.is_active
     and m.deleted_at is null
     and (m.branch_id is null or m.branch_id = v_p.storefront_branch_id)
     and i.is_active and i.deleted_at is null and (i.branch_id is null or i.branch_id = v_p.storefront_branch_id)
     and c.is_active and c.deleted_at is null and (c.branch_id is null or c.branch_id = v_p.storefront_branch_id);

  -- (h) live options of LIVE modifiers (kiosk_menu (i) VERBATIM); a NEGATIVE
  --     delta is excluded (the Storefront renders a negative delta as
  --     "included"); no kitchen_meat
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', mo.id, 'modifier_id', mo.modifier_id, 'name', left(mo.name, 80),
             'price_delta_minor', mo.price_delta_minor, 'display_order', mo.display_order)
           order by mo.display_order, mo.name), '[]'::jsonb),
         greatest(v_max_updated, max(mo.updated_at))
    into v_options, v_max_updated
    from public.modifier_options mo
    join public.modifiers m
      on m.organization_id = mo.organization_id and m.id = mo.modifier_id
    join public.menu_items i
      on i.organization_id = m.organization_id
     and i.restaurant_id   = v_p.restaurant_id
     and i.id = m.menu_item_id
    join public.menu_categories c
      on c.organization_id = i.organization_id
     and c.restaurant_id   = v_p.restaurant_id
     and c.id = i.menu_category_id
   where mo.organization_id = v_p.organization_id
     and mo.restaurant_id = v_p.restaurant_id
     and mo.is_active
     and mo.deleted_at is null
     and mo.price_delta_minor >= 0
     and (mo.branch_id is null or mo.branch_id = v_p.storefront_branch_id)
     and m.is_active and m.deleted_at is null and (m.branch_id is null or m.branch_id = v_p.storefront_branch_id)
     and i.is_active and i.deleted_at is null and (i.branch_id is null or i.branch_id = v_p.storefront_branch_id)
     and c.is_active and c.deleted_at is null and (c.branch_id is null or c.branch_id = v_p.storefront_branch_id);

  -- (i) payload caps: typed, never disguised as not_found
  if jsonb_array_length(v_categories) > c_cap_cat or jsonb_array_length(v_items) > c_cap_item
     or jsonb_array_length(v_modifiers) > c_cap_mod or jsonb_array_length(v_options) > c_cap_opt then
    return jsonb_build_object('ok', false, 'error', 'payload_limit', 'entity', 'storefront_menu');
  end if;

  -- (j) the cart key: profile version + the newest catalog change (availability
  --     flips deliberately excluded so a sold-out toggle does not reset carts)
  v_menu_version := v_p.version::text || '.' ||
                    coalesce(floor(extract(epoch from greatest(v_max_updated, v_p.updated_at)))::bigint::text, '0');

  return jsonb_build_object(
    'ok', true,
    'entity', 'storefront_menu',
    'menu_version', v_menu_version,
    'server_ts', v_now,
    'restaurant', jsonb_build_object(
      'slug', v_p.slug, 'display_name', v_p.display_name, 'tagline', v_p.tagline,
      'city', v_p.public_city, 'address', v_p.public_address, 'phone', v_p.public_phone,
      'primary_color', v_p.primary_color, 'accent_color', v_p.accent_color,
      'logo_url', v_logo, 'hero_url', v_hero,
      'currency_code', v_p.currency, 'locale_default', v_p.locale_default,
      'visual_preset', v_p.visual_preset, 'card_mode', v_p.card_mode, 'motion', v_p.motion),
    'hours', jsonb_build_object(
      'timezone', v_p.tz, 'opens', v_hours.opens, 'closes', v_hours.closes,
      'open_now', v_hours.open_now, 'next_open', v_hours.next_open),
    'service', jsonb_build_object(
      'state', v_state, 'ordering_enabled', false,
      'pickup_enabled', v_p.pickup_enabled, 'delivery_enabled', false),
    'tax', jsonb_build_object('enabled', v_p.tax_enabled, 'rate_bp', v_p.tax_rate_bp, 'mode', v_p.tax_mode),
    'categories', v_categories,
    'items', v_items,
    'modifiers', v_modifiers,
    'modifier_options', v_options);
end;
$$;

-- CREATE OR REPLACE preserves function ownership, ACLs and the existing public
-- wrappers. Restate the private helper boundary explicitly for auditability.
revoke all on function app.price_web_order(text,jsonb),
  app.decide_pos_web_order(uuid,uuid,text,uuid,uuid,text,text)
  from public,anon,authenticated,service_role;

commit;
