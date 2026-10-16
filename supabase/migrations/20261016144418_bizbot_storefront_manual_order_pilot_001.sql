-- BIZBOT-STOREFRONT-MANUAL-ORDER-PILOT-001: default-OFF owner-operated Pickup pilot.
-- Installs capability only: NO pilot/channel/profile/policy rows are activated.
begin;

create table app.storefront_manual_order_pilots (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  restaurant_id uuid not null,
  branch_id uuid not null unique,
  enabled boolean not null default false,
  starts_at timestamptz not null,
  expires_at timestamptz not null,
  contact_salt text not null check (contact_salt ~ '^[0-9a-f]{64}$'),
  contact_hash text not null check (contact_hash ~ '^[0-9a-f]{64}$'),
  consumed_client_request_id uuid,
  consumed_request_id uuid references public.web_order_requests(id),
  consumed_at timestamptz,
  closed_at timestamptz,
  operator_reference text not null check (length(operator_reference) between 1 and 240),
  created_at timestamptz not null default clock_timestamp(),
  foreign key (organization_id,restaurant_id,branch_id)
    references public.branches(organization_id,restaurant_id,id),
  constraint manual_pilot_mapsburger_only check (
    organization_id='20605c2b-3145-4803-a990-bbec3d9c1096'::uuid
    and restaurant_id='de3bbc64-edad-4ff4-bccd-c2ef217c1d56'::uuid
    and branch_id='2847c0be-3e31-45a5-957c-508729f1971e'::uuid),
  constraint manual_pilot_bounded_window check (
    isfinite(starts_at) and isfinite(expires_at) and expires_at>starts_at
    and expires_at-starts_at<=interval '15 minutes'),
  constraint manual_pilot_consumed_shape check (
    (consumed_client_request_id is null and consumed_request_id is null and consumed_at is null)
    or (consumed_client_request_id is not null and consumed_request_id is not null
      and consumed_at is not null and not enabled and closed_at is not null))
);
alter table app.storefront_manual_order_pilots enable row level security;
alter table app.storefront_manual_order_pilots force row level security;
revoke all on app.storefront_manual_order_pilots from public,anon,authenticated,service_role;

create function app.guard_storefront_manual_order_pilot()
returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op in ('DELETE','TRUNCATE') then
    raise exception 'manual pilot evidence is retained' using errcode='42501';
  end if;
  if (to_jsonb(new)-array['enabled','consumed_client_request_id','consumed_request_id','consumed_at','closed_at'])
     is distinct from (to_jsonb(old)-array['enabled','consumed_client_request_id','consumed_request_id','consumed_at','closed_at'])
     or (not old.enabled and new.enabled)
     or (old.consumed_request_id is not null and
       (new.consumed_client_request_id,new.consumed_request_id,new.consumed_at)
       is distinct from (old.consumed_client_request_id,old.consumed_request_id,old.consumed_at))
     or (old.closed_at is not null and new.closed_at is distinct from old.closed_at) then
    raise exception 'manual pilot identity/budget is immutable' using errcode='42501';
  end if;
  return new;
end;
$$;
revoke all on function app.guard_storefront_manual_order_pilot() from public,anon,authenticated,service_role;
create trigger manual_pilot_guard before update or delete on app.storefront_manual_order_pilots
for each row execute function app.guard_storefront_manual_order_pilot();
create trigger manual_pilot_no_truncate before truncate on app.storefront_manual_order_pilots
for each statement execute function app.guard_storefront_manual_order_pilot();

create function app.storefront_manual_order_pilot_open(p_slug text)
returns boolean language sql volatile security definer set search_path='' as $$
  select p_slug='mapsburger' and exists (
    select 1 from app.storefront_manual_order_pilots p
    join public.restaurant_storefront_profiles s on s.organization_id=p.organization_id
      and s.restaurant_id=p.restaurant_id and s.storefront_branch_id=p.branch_id
    join public.web_order_channel_settings c on c.organization_id=p.organization_id
      and c.restaurant_id=p.restaurant_id and c.branch_id=p.branch_id
    where s.slug=p_slug and s.deleted_at is null and s.is_published and s.pickup_enabled
      and not s.delivery_enabled and p.enabled and p.consumed_request_id is null
      and clock_timestamp()>=p.starts_at and clock_timestamp()<p.expires_at
      and c.submission_enabled
      and app.kitchen_print_containment_state(p.organization_id,p.restaurant_id,p.branch_id)->>'mode'='blocked'
  );
$$;
revoke all on function app.storefront_manual_order_pilot_open(text) from public,anon,authenticated,service_role;

-- Keep the existing strict reader and profile browse-only CHECK intact. The
-- wrapper changes ONLY its existing service.ordering_enabled bit, never shape,
-- public price authority, media paths or tenant identifiers.
alter function public.storefront_menu(text) rename to storefront_menu_browse_only_manual_pilot_001;
alter function public.storefront_menu_browse_only_manual_pilot_001(text) set schema app;
revoke all on function app.storefront_menu_browse_only_manual_pilot_001(text)
  from public,anon,authenticated,service_role;
create function public.storefront_menu(p_slug text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v jsonb;
begin
  v:=app.storefront_menu_browse_only_manual_pilot_001(p_slug);
  if v->>'ok'='true' then
    v:=jsonb_set(v,'{service,ordering_enabled}',to_jsonb(
      v->'service'->>'state'='open' and (v->'service'->>'pickup_enabled')::boolean
      and app.storefront_manual_order_pilot_open(p_slug)));
  end if;
  return v;
end;
$$;
revoke all on function public.storefront_menu(text) from public,anon,authenticated,service_role;
grant execute on function public.storefront_menu(text) to anon,service_role;

create function app.submit_web_order_pilot_request(
  p_slug text,p_client_request_id uuid,p_status_token_hash text,p_order jsonb
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare
  v_pilot app.storefront_manual_order_pilots;
  v_now timestamptz;
  v_result jsonb;
  v_request_id uuid;
begin
  if p_slug is distinct from 'mapsburger' or p_client_request_id is null
     or p_order->>'order_type' is distinct from 'takeaway' then
    return jsonb_build_object('ok',false,'error','ordering_unavailable');
  end if;
  -- Shared identity lock BEFORE pilot/channel locks. Concurrent distinct
  -- browser identities serialize on this one pilot row, not a rolling query.
  perform pg_advisory_xact_lock(hashtextextended(
    'de3bbc64-edad-4ff4-bccd-c2ef217c1d56:'||p_client_request_id::text,0));
  perform 1 from public.restaurant_storefront_profiles s
    where s.slug=p_slug and s.organization_id='20605c2b-3145-4803-a990-bbec3d9c1096'
      and s.restaurant_id='de3bbc64-edad-4ff4-bccd-c2ef217c1d56'
      and s.storefront_branch_id='2847c0be-3e31-45a5-957c-508729f1971e'
      and s.deleted_at is null for share;
  if not found then return jsonb_build_object('ok',false,'error','ordering_unavailable'); end if;
  select * into v_pilot from app.storefront_manual_order_pilots
    where branch_id='2847c0be-3e31-45a5-957c-508729f1971e' for update;
  if not found then return jsonb_build_object('ok',false,'error','ordering_unavailable'); end if;
  if v_pilot.consumed_request_id is not null then
    if v_pilot.consumed_client_request_id<>p_client_request_id then
      return jsonb_build_object('ok',false,'error','ordering_unavailable');
    end if;
    -- Exact payload/capability recovery survives expiry and kill. Delegation
    -- enforces both hashes and captured branch; cannot create a second row.
    return app.submit_web_order_request(p_slug,p_client_request_id,p_status_token_hash,p_order);
  end if;
  v_now:=clock_timestamp();
  if not v_pilot.enabled or v_now<v_pilot.starts_at or v_now>=v_pilot.expires_at
     or not app.storefront_manual_order_pilot_open(p_slug)
     or exists(select 1 from public.web_order_requests
       where restaurant_id=v_pilot.restaurant_id and client_request_id=p_client_request_id)
     or encode(sha256(convert_to(v_pilot.contact_salt||E'\n'||
       lower(btrim(p_order->'customer'->>'name'))||E'\n'||
       (p_order->'customer'->>'phone'),'UTF8')),'hex') is distinct from v_pilot.contact_hash then
    return jsonb_build_object('ok',false,'error','ordering_unavailable');
  end if;
  -- Unchanged validation, authoritative quote, modifiers, tax, quotas and
  -- expiry. No canonical order/acceptance/printer function is invoked here.
  v_result:=app.submit_web_order_request(p_slug,p_client_request_id,p_status_token_hash,p_order);
  if v_result->>'ok' is distinct from 'true' then return v_result; end if;
  v_now:=clock_timestamp();
  if v_now<v_pilot.starts_at or v_now>=v_pilot.expires_at then
    raise exception using errcode='RMP01',message='manual pilot expired during submission';
  end if;
  select id into v_request_id from public.web_order_requests
    where organization_id=v_pilot.organization_id and restaurant_id=v_pilot.restaurant_id
      and branch_id=v_pilot.branch_id and client_request_id=p_client_request_id
      and status_token_hash=p_status_token_hash and status='pending';
  if v_request_id is null or v_result->>'replayed' is distinct from 'false' then
    raise exception using errcode='RMP01',message='manual pilot request mapping failed';
  end if;
  update app.storefront_manual_order_pilots set enabled=false,
    consumed_client_request_id=p_client_request_id,consumed_request_id=v_request_id,
    consumed_at=v_now,closed_at=v_now where id=v_pilot.id;
  update public.web_order_channel_settings set submission_enabled=false,updated_at=v_now
    where organization_id=v_pilot.organization_id and restaurant_id=v_pilot.restaurant_id
      and branch_id=v_pilot.branch_id;
  return v_result;
exception when sqlstate 'RMP01' then
  -- Entire delegated insert, events and counters roll back on late expiry.
  return jsonb_build_object('ok',false,'error','ordering_unavailable');
end;
$$;
create function public.submit_web_order_pilot_request(
  p_slug text,p_client_request_id uuid,p_status_token_hash text,p_order jsonb
) returns jsonb language sql volatile security invoker set search_path='' as $$
  select app.submit_web_order_pilot_request(p_slug,p_client_request_id,p_status_token_hash,p_order);
$$;
revoke all on function app.submit_web_order_pilot_request(text,uuid,text,jsonb),
  public.submit_web_order_pilot_request(text,uuid,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function app.submit_web_order_pilot_request(text,uuid,text,jsonb),
  public.submit_web_order_pilot_request(text,uuid,text,jsonb) to service_role;

commit;
