-- BIZBOT-STOREFRONT-MANUAL-ORDER-PILOT-001: renewable UNUSED windows,
-- with one successful request TOTAL for the exact branch. SOURCE ONLY.
-- No existing pilot row, deadline, consumed identity or production setting is
-- rewritten. An expired enabled window must first be explicitly closed.
begin;

alter table app.storefront_manual_order_pilots
  drop constraint storefront_manual_order_pilots_branch_id_key;
create unique index storefront_manual_order_pilots_one_enabled_branch
  on app.storefront_manual_order_pilots(branch_id) where enabled;
create unique index storefront_manual_order_pilots_one_consumed_branch
  on app.storefront_manual_order_pilots(branch_id) where consumed_request_id is not null;

create or replace function app.guard_storefront_manual_order_pilot()
returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op in ('DELETE','TRUNCATE') then
    raise exception 'manual pilot evidence is retained' using errcode='42501';
  end if;
  if tg_op='INSERT' then
    -- Serialize renewal with submission and operator closure. There is no
    -- rolling counter reset: every historical consumed identity remains final.
    perform app.lock_kitchen_print_containment(new.branch_id,true);
    if new.consumed_client_request_id is not null or new.consumed_request_id is not null
      or new.consumed_at is not null
      or exists(select 1 from app.storefront_manual_order_pilots p
        where p.branch_id=new.branch_id and (p.consumed_request_id is not null
          or p.enabled or (p.closed_at is null and p.expires_at>clock_timestamp()))) then
      raise exception 'manual pilot branch budget or unused window is not closed' using errcode='42501';
    end if;
    return new;
  end if;
  perform app.lock_kitchen_print_containment(old.branch_id,false);
  if (to_jsonb(new)-array['enabled','consumed_client_request_id','consumed_request_id','consumed_at','closed_at'])
     is distinct from (to_jsonb(old)-array['enabled','consumed_client_request_id','consumed_request_id','consumed_at','closed_at'])
     or (not old.enabled and new.enabled)
     or (old.consumed_request_id is not null and
       (new.consumed_client_request_id,new.consumed_request_id,new.consumed_at)
       is distinct from (old.consumed_client_request_id,old.consumed_request_id,old.consumed_at))
     or (old.closed_at is not null and new.closed_at is distinct from old.closed_at) then
    raise exception 'manual pilot identity/budget is immutable' using errcode='42501';
  end if;
  if old.consumed_request_id is null and new.consumed_request_id is not null
    and (not old.enabled or exists(select 1 from app.storefront_manual_order_pilots p
      where p.branch_id=old.branch_id and p.id<>old.id and p.consumed_request_id is not null)) then
    raise exception 'manual pilot branch budget is already consumed or window was closed' using errcode='42501';
  end if;
  return new;
end;
$$;
revoke all on function app.guard_storefront_manual_order_pilot() from public,anon,authenticated,service_role;
create trigger manual_pilot_insert_guard before insert on app.storefront_manual_order_pilots
for each row execute function app.guard_storefront_manual_order_pilot();

create or replace function app.storefront_manual_order_pilot_open(p_slug text)
returns boolean language sql stable security definer set search_path='' as $$
  select p_slug='mapsburger' and exists (
    select 1 from app.storefront_manual_order_pilots p
    join public.restaurant_storefront_profiles s on s.organization_id=p.organization_id
      and s.restaurant_id=p.restaurant_id and s.storefront_branch_id=p.branch_id
    join public.web_order_channel_settings c on c.organization_id=p.organization_id
      and c.restaurant_id=p.restaurant_id and c.branch_id=p.branch_id
    where s.slug=p_slug and s.deleted_at is null and s.is_published and s.pickup_enabled
      and not s.delivery_enabled and p.enabled and p.consumed_request_id is null
      and statement_timestamp()>=p.starts_at and statement_timestamp()<p.expires_at
      and c.submission_enabled
      and not exists(select 1 from app.storefront_manual_order_pilots prior
        where prior.branch_id=p.branch_id and prior.consumed_request_id is not null)
      and app.kitchen_print_containment_state(p.organization_id,p.restaurant_id,p.branch_id)->>'mode'='blocked'
  );
$$;

create or replace function app.submit_web_order_pilot_request(
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
  -- Common branch fence BEFORE identity/profile/pilot locks. Renewal operators
  -- take its exclusive form; concurrent submissions share it and serialize on
  -- the one enabled row. Existing delegate identity/channel locks are retained.
  perform app.lock_kitchen_print_containment('2847c0be-3e31-45a5-957c-508729f1971e',false);
  perform pg_advisory_xact_lock(hashtextextended(
    'de3bbc64-edad-4ff4-bccd-c2ef217c1d56:'||p_client_request_id::text,0));
  perform 1 from public.restaurant_storefront_profiles s
    where s.slug=p_slug and s.organization_id='20605c2b-3145-4803-a990-bbec3d9c1096'
      and s.restaurant_id='de3bbc64-edad-4ff4-bccd-c2ef217c1d56'
      and s.storefront_branch_id='2847c0be-3e31-45a5-957c-508729f1971e'
      and s.deleted_at is null for share;
  if not found then return jsonb_build_object('ok',false,'error','ordering_unavailable'); end if;

  -- A consumed row anywhere in this branch owns the lifetime budget. Exact
  -- original recovery survives every closed/expired window and channel pause.
  select * into v_pilot from app.storefront_manual_order_pilots
    where branch_id='2847c0be-3e31-45a5-957c-508729f1971e'
      and consumed_request_id is not null for update;
  if found then
    if v_pilot.consumed_client_request_id<>p_client_request_id then
      return jsonb_build_object('ok',false,'error','ordering_unavailable');
    end if;
    return app.submit_web_order_request(p_slug,p_client_request_id,p_status_token_hash,p_order);
  end if;
  select * into v_pilot from app.storefront_manual_order_pilots
    where branch_id='2847c0be-3e31-45a5-957c-508729f1971e' and enabled for update;
  if not found then return jsonb_build_object('ok',false,'error','ordering_unavailable'); end if;
  v_now:=clock_timestamp();
  if v_now<v_pilot.starts_at or v_now>=v_pilot.expires_at
     or not app.storefront_manual_order_pilot_open(p_slug)
     or exists(select 1 from public.web_order_requests
       where restaurant_id=v_pilot.restaurant_id and client_request_id=p_client_request_id)
     or encode(sha256(convert_to(v_pilot.contact_salt||E'\n'||
       lower(btrim(p_order->'customer'->>'name'))||E'\n'||
       (p_order->'customer'->>'phone'),'UTF8')),'hex') is distinct from v_pilot.contact_hash then
    return jsonb_build_object('ok',false,'error','ordering_unavailable');
  end if;
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
  return jsonb_build_object('ok',false,'error','ordering_unavailable');
end;
$$;

commit;
