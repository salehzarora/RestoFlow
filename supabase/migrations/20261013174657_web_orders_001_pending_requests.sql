-- WEB-ORDERS-001: customer intent is a private pending request, NOT an order.
-- No existing RPC/table/policy is replaced. No channel is enabled or seeded.
begin;

create table public.web_order_channel_settings (
  organization_id uuid not null,
  restaurant_id uuid not null,
  branch_id uuid primary key,
  submission_enabled boolean not null default false,
  submit_window_started_at timestamptz not null default 'epoch',
  submit_attempt_count integer not null default 0 check (submit_attempt_count >= 0),
  submitted_in_window integer not null default 0 check (submitted_in_window >= 0),
  submit_day date not null default '1970-01-01',
  submitted_today integer not null default 0 check (submitted_today >= 0),
  status_window_started_at timestamptz not null default 'epoch',
  status_attempt_count integer not null default 0 check (status_attempt_count >= 0),
  updated_at timestamptz not null default now(),
  unique (organization_id, restaurant_id, branch_id),
  foreign key (organization_id, restaurant_id, branch_id)
    references public.branches (organization_id, restaurant_id, id) on delete restrict
);

create table public.web_order_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  restaurant_id uuid not null,
  branch_id uuid not null,
  client_request_id uuid not null,
  status_token_hash text not null check (status_token_hash ~ '^[0-9a-f]{64}$'),
  payload_hash text not null check (payload_hash ~ '^[0-9a-f]{64}$'),
  order_type text not null default 'takeaway' check (order_type = 'takeaway'),
  customer_name text not null check (length(btrim(customer_name)) between 1 and 80),
  customer_phone text not null check (customer_phone ~ '^\+[1-9][0-9]{7,14}$'),
  notes text not null default '' check (length(notes) <= 500),
  priced_items jsonb not null check (jsonb_typeof(priced_items) = 'array'
    and jsonb_array_length(priced_items) between 1 and 20),
  currency_code text not null check (currency_code = 'ILS'),
  subtotal_minor bigint not null check (subtotal_minor between 0 and 10000000),
  tax_total_minor bigint not null check (tax_total_minor between 0 and 10000000),
  grand_total_minor bigint not null check (grand_total_minor between 0 and 10000000
    and grand_total_minor = subtotal_minor + tax_total_minor),
  status text not null default 'pending'
    check (status in ('pending','accepted','rejected','expired')),
  canonical_order_id uuid,
  rejection_reason text check (length(rejection_reason) <= 240),
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  status_until timestamptz not null,
  unique (restaurant_id, client_request_id),
  unique (organization_id, restaurant_id, branch_id, id),
  foreign key (organization_id, restaurant_id, branch_id)
    references public.web_order_channel_settings
      (organization_id, restaurant_id, branch_id) on delete restrict,
  foreign key (organization_id, canonical_order_id)
    references public.orders (organization_id, id) on delete restrict,
  check (expires_at > created_at and expires_at <= created_at + interval '15 minutes'),
  check (status_until > expires_at and status_until <= created_at + interval '24 hours'),
  check ((status = 'accepted') = (canonical_order_id is not null)),
  check ((status in ('accepted','rejected')) = (decided_at is not null)),
  check (status = 'rejected' or rejection_reason is null)
);
create index web_order_requests_pending_scope_idx on public.web_order_requests
  (organization_id, restaurant_id, branch_id, expires_at) where status = 'pending';
create index web_order_requests_pending_phone_idx on public.web_order_requests
  (branch_id, customer_phone, expires_at) where status = 'pending';
create unique index web_order_requests_canonical_once_idx on public.web_order_requests
  (canonical_order_id) where canonical_order_id is not null;

create table public.web_order_request_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  restaurant_id uuid not null,
  branch_id uuid not null,
  request_id uuid not null,
  event_type text not null check (event_type = 'received'),
  created_at timestamptz not null default now(),
  unique (request_id, event_type),
  foreign key (organization_id, restaurant_id, branch_id, request_id)
    references public.web_order_requests
      (organization_id, restaurant_id, branch_id, id) on delete restrict
);
create trigger web_order_request_events_append_only
  before update or delete on public.web_order_request_events
  for each row execute function app.enforce_audit_append_only();
create trigger web_order_request_events_no_truncate
  before truncate on public.web_order_request_events
  for each statement execute function app.enforce_audit_append_only();

alter table public.web_order_channel_settings enable row level security;
alter table public.web_order_channel_settings force row level security;
alter table public.web_order_requests enable row level security;
alter table public.web_order_requests force row level security;
alter table public.web_order_request_events enable row level security;
alter table public.web_order_request_events force row level security;
-- RF-059 requires explicit per-command policies even for RPC-only deny tables.
create policy web_order_channel_settings_select on public.web_order_channel_settings
  for select to authenticated using (false);
create policy web_order_channel_settings_insert on public.web_order_channel_settings
  for insert to authenticated with check (false);
create policy web_order_channel_settings_update on public.web_order_channel_settings
  for update to authenticated using (false) with check (false);
create policy web_order_channel_settings_delete on public.web_order_channel_settings
  for delete to authenticated using (false);
create policy web_order_requests_select on public.web_order_requests
  for select to authenticated using (false);
create policy web_order_requests_insert on public.web_order_requests
  for insert to authenticated with check (false);
create policy web_order_requests_update on public.web_order_requests
  for update to authenticated using (false) with check (false);
create policy web_order_requests_delete on public.web_order_requests
  for delete to authenticated using (false);
create policy web_order_request_events_select on public.web_order_request_events
  for select to authenticated using (false);
create policy web_order_request_events_insert on public.web_order_request_events
  for insert to authenticated with check (false);
create policy web_order_request_events_update on public.web_order_request_events
  for update to authenticated using (false) with check (false);
create policy web_order_request_events_delete on public.web_order_request_events
  for delete to authenticated using (false);
revoke all on public.web_order_channel_settings, public.web_order_requests,
  public.web_order_request_events from public, anon, authenticated, service_role;

comment on table public.web_order_requests is
  'WEB-ORDERS-001: immutable server-priced customer intent, scoped by published slug. Not a canonical order, payment, kitchen dispatch or receipt. Private PII and capability hashes; no direct client access. Only a separately implemented trusted POS acceptance may link a same-scope canonical order.';
comment on table public.web_order_channel_settings is
  'WEB-ORDERS-001: separately controlled, default-OFF branch admission gate and fixed-size abuse counters. No rows or enables are installed by this migration; no client/manager activation API.';
comment on table public.web_order_request_events is
  'WEB-ORDERS-001: append-only anonymous-customer receipt ledger, no PII/token and no fabricated staff actor. Future staff decisions require a separately authorized contract.';

create function app.guard_web_order_request() returns trigger
language plpgsql set search_path = '' as $$
begin
  if (to_jsonb(new) - array['status','canonical_order_id','rejection_reason','decided_at'])
       is distinct from
     (to_jsonb(old) - array['status','canonical_order_id','rejection_reason','decided_at']) then
    raise exception 'web order identity and quote are immutable' using errcode = '42501';
  end if;
  if old.status <> 'pending' or new.status = 'pending' then
    raise exception 'web order decision is terminal' using errcode = '42501';
  end if;
  if new.status in ('accepted','rejected') and old.expires_at <= clock_timestamp() then
    raise exception 'web order request expired' using errcode = '42501';
  end if;
  if new.status = 'expired' and old.expires_at > clock_timestamp() then
    raise exception 'web order request has not expired' using errcode = '42501';
  end if;
  if new.status = 'accepted' and not exists (
    select 1 from public.orders o where o.id = new.canonical_order_id
      and o.organization_id = old.organization_id and o.restaurant_id = old.restaurant_id
      and o.branch_id = old.branch_id and o.order_type = 'takeaway' and o.deleted_at is null
  ) then
    raise exception 'canonical order is not in request scope' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function app.guard_web_order_request() from public, anon, authenticated, service_role;
create trigger web_order_request_guard before update on public.web_order_requests
  for each row execute function app.guard_web_order_request();

create function app.web_order_public_result(
  p_request public.web_order_requests, p_replayed boolean
) returns jsonb language sql volatile set search_path = '' as $$
  select jsonb_build_object(
    'ok',true,'request_id',p_request.client_request_id,
    'status',case when p_request.status='pending' and p_request.expires_at<=clock_timestamp()
                  then 'expired' else p_request.status end,
    'expires_at',p_request.expires_at,
    'totals',jsonb_build_object('currency_code',p_request.currency_code,
      'subtotal_minor',p_request.subtotal_minor,'tax_total_minor',p_request.tax_total_minor,
      'grand_total_minor',p_request.grand_total_minor),
    'replayed',p_replayed);
$$;
revoke all on function app.web_order_public_result(public.web_order_requests,boolean)
  from public, anon, authenticated, service_role;

-- A STABLE pricing call reads one coherent current catalog snapshot. All money
-- and names come from that snapshot, never customer-provided snapshots/totals.
create function app.price_web_order(p_slug text,p_items jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_profile public.restaurant_storefront_profiles;
  v_menu jsonb; v_line jsonb; v_item jsonb; v_mod jsonb; v_option jsonb;
  v_group record; v_options jsonb; v_lines jsonb := '[]'; v_id uuid; v_option_id uuid;
  v_seen uuid[]; v_qty bigint; v_opt_qty bigint; v_unit bigint; v_delta bigint;
  v_mod_sum bigint; v_line_total bigint; v_subtotal bigint:=0; v_tax bigint; v_total_units integer:=0;
  v_count integer; v_min integer; v_max integer; v_group_qty bigint;
begin
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
                 where k not in ('menu_item_id','quantity','modifiers'))
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
      'modifiers',v_options,'line_total_minor',v_line_total));
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
revoke all on function app.price_web_order(text,jsonb) from public,anon,authenticated,service_role;

create function app.submit_web_order_request(
  p_slug text,p_client_request_id uuid,p_status_token_hash text,p_order jsonb
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_profile public.restaurant_storefront_profiles;
  v_channel public.web_order_channel_settings;
  v_request public.web_order_requests;
  v_now timestamptz:=clock_timestamp(); v_day date; v_payload_hash text;
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

create function app.get_web_order_request_status(
  p_slug text,p_client_request_id uuid,p_status_token_hash text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  v_profile public.restaurant_storefront_profiles;
  v_request public.web_order_requests; v_channel public.web_order_channel_settings;
  v_branch uuid; v_found boolean; v_now timestamptz;
begin
  if p_slug is null or length(p_slug) not between 3 and 48
     or p_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or p_client_request_id is null
     or p_status_token_hash is null or p_status_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok',false,'error','not_found');
  end if;
  select * into v_profile from public.restaurant_storefront_profiles
    where slug=p_slug and deleted_at is null;
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
  select * into v_request from public.web_order_requests
    where restaurant_id=v_profile.restaurant_id and client_request_id=p_client_request_id;
  v_found:=found; v_branch:=case when v_found then v_request.branch_id else v_profile.storefront_branch_id end;
  select * into v_channel from public.web_order_channel_settings
    where organization_id=v_profile.organization_id and restaurant_id=v_profile.restaurant_id
      and branch_id=v_branch for update;
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
  v_now:=clock_timestamp();
  if v_channel.status_window_started_at<=v_now-interval '1 minute' then
    v_channel.status_window_started_at:=v_now; v_channel.status_attempt_count:=0;
  end if;
  -- Re-read after lock wait so a future cashier decision is not hidden by an
  -- earlier snapshot retained while admission was blocked. An exhausted quota
  -- must not turn an invalid capability into a private-slug existence oracle.
  select * into v_request from public.web_order_requests
    where restaurant_id=v_profile.restaurant_id and client_request_id=p_client_request_id
      and status_token_hash=p_status_token_hash and status_until>v_now;
  v_found:=found;
  if v_channel.status_attempt_count>=600 then
    return jsonb_build_object('ok',false,'error',case when v_found then 'rate_limited' else 'not_found' end);
  end if;
  update public.web_order_channel_settings set status_window_started_at=v_channel.status_window_started_at,
    status_attempt_count=v_channel.status_attempt_count+1,updated_at=v_now where branch_id=v_branch;
  if not v_found then
    return jsonb_build_object('ok',false,'error','not_found');
  end if;
  return app.web_order_public_result(v_request,false);
end;
$$;

-- Exact service-only wrappers preserve the existing public INVOKER pattern.
grant usage on schema app to service_role;
create function public.submit_web_order_request(
  p_slug text,p_client_request_id uuid,p_status_token_hash text,p_order jsonb
) returns jsonb language sql security invoker set search_path = '' as $$
  select app.submit_web_order_request(p_slug,p_client_request_id,p_status_token_hash,p_order);
$$;
create function public.get_web_order_request_status(
  p_slug text,p_client_request_id uuid,p_status_token_hash text
) returns jsonb language sql security invoker set search_path = '' as $$
  select app.get_web_order_request_status(p_slug,p_client_request_id,p_status_token_hash);
$$;
revoke all on function public.submit_web_order_request(text,uuid,text,jsonb),
  app.submit_web_order_request(text,uuid,text,jsonb),
  public.get_web_order_request_status(text,uuid,text),
  app.get_web_order_request_status(text,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.submit_web_order_request(text,uuid,text,jsonb),
  app.submit_web_order_request(text,uuid,text,jsonb),
  public.get_web_order_request_status(text,uuid,text),
  app.get_web_order_request_status(text,uuid,text) to service_role;
alter function app.submit_web_order_request(text,uuid,text,jsonb) owner to postgres;
alter function app.get_web_order_request_status(text,uuid,text) owner to postgres;

commit;
