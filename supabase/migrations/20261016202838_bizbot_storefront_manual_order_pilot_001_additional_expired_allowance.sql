-- BIZBOT-STOREFRONT-MANUAL-ORDER-PILOT-001: ONE additional owner-authorized
-- allowance after an unaccepted request expires. Capability only/default OFF.
-- Existing pilot/request rows remain byte-identical. No activation or seed.
begin;

create table app.storefront_manual_order_pilot_extra_allowance (
  singleton boolean primary key default true check (singleton),
  pilot_id uuid not null unique,
  previous_pilot_id uuid not null unique,
  previous_request_id uuid not null unique,
  organization_id uuid not null,
  restaurant_id uuid not null,
  branch_id uuid not null,
  starts_at timestamptz not null,
  expires_at timestamptz not null,
  operator_reference text not null check (length(operator_reference) between 1 and 240),
  authorized_at timestamptz not null default clock_timestamp(),
  check (pilot_id<>previous_pilot_id),
  check (isfinite(starts_at) and isfinite(expires_at) and expires_at>starts_at
    and expires_at-starts_at<=interval '15 minutes'),
  check (organization_id='20605c2b-3145-4803-a990-bbec3d9c1096'::uuid
    and restaurant_id='de3bbc64-edad-4ff4-bccd-c2ef217c1d56'::uuid
    and branch_id='2847c0be-3e31-45a5-957c-508729f1971e'::uuid),
  foreign key (organization_id,restaurant_id,branch_id)
    references public.branches(organization_id,restaurant_id,id)
);
alter table app.storefront_manual_order_pilot_extra_allowance enable row level security;
alter table app.storefront_manual_order_pilot_extra_allowance force row level security;
revoke all on app.storefront_manual_order_pilot_extra_allowance
  from public,anon,authenticated,service_role;

-- The operator cannot mint an unbounded series: this table has exactly one
-- possible singleton row, cannot be rewritten/deleted, and binds one future
-- pilot identity. The deferred link trigger below requires that exact pilot
-- in the same commit while preserving the old 42501 audit-retention contract.
create function app.guard_manual_order_pilot_extra_allowance()
returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op<>'INSERT' then
    raise exception 'additional pilot authorization is immutable' using errcode='42501';
  end if;
  perform app.lock_kitchen_print_containment(new.branch_id,true);
  if new.expires_at<=clock_timestamp() or new.starts_at>clock_timestamp()+interval '1 minute'
    or not exists (
      select 1 from app.storefront_manual_order_pilots p
      join public.web_order_requests w on w.id=p.consumed_request_id
      where p.id=new.previous_pilot_id and w.id=new.previous_request_id
        and p.organization_id=new.organization_id and p.restaurant_id=new.restaurant_id
        and p.branch_id=new.branch_id and w.organization_id=p.organization_id
        and w.restaurant_id=p.restaurant_id and w.branch_id=p.branch_id
        and not p.enabled and p.closed_at is not null and p.consumed_at is not null
        and w.status in ('pending','expired') and w.expires_at<=clock_timestamp()
        and w.canonical_order_id is null
        and not exists(select 1 from public.web_order_decisions d where d.request_id=w.id)
        and not exists(select 1 from public.web_order_print_attempts a where a.request_id=w.id)
    )
    or exists(select 1 from app.storefront_manual_order_pilots p
      where p.branch_id=new.branch_id and (p.enabled or
        (p.consumed_request_id is not null and p.id<>new.previous_pilot_id)))
    or exists(select 1 from public.web_order_requests w where w.branch_id=new.branch_id
      and w.status='pending' and w.expires_at>clock_timestamp())
    or app.kitchen_print_containment_state(new.organization_id,new.restaurant_id,new.branch_id)->>'mode'
      is distinct from 'blocked' then
    raise exception 'additional pilot authorization prerequisites not satisfied' using errcode='42501';
  end if;
  return new;
end;
$$;
revoke all on function app.guard_manual_order_pilot_extra_allowance()
  from public,anon,authenticated,service_role;
create trigger manual_pilot_extra_allowance_guard before insert or update or delete
  on app.storefront_manual_order_pilot_extra_allowance for each row
  execute function app.guard_manual_order_pilot_extra_allowance();
create trigger manual_pilot_extra_allowance_no_truncate before truncate
  on app.storefront_manual_order_pilot_extra_allowance for each statement
  execute function app.guard_manual_order_pilot_extra_allowance();

-- Private predicate, called with a fresh wall-clock AFTER the protected lock
-- for mutations, or statement time for the read-only public ordering hint.
create function app.manual_order_pilot_extra_allowed(
  p app.storefront_manual_order_pilots,p_now timestamptz
) returns boolean language sql stable set search_path='' as $$
  select exists (
    select 1 from app.storefront_manual_order_pilot_extra_allowance g
    join app.storefront_manual_order_pilots prior on prior.id=g.previous_pilot_id
    join public.web_order_requests w on w.id=g.previous_request_id
    where g.pilot_id=(p).id and g.organization_id=(p).organization_id
      and g.restaurant_id=(p).restaurant_id and g.branch_id=(p).branch_id
      and g.starts_at=(p).starts_at and g.expires_at=(p).expires_at
      and g.operator_reference=(p).operator_reference and p_now<g.expires_at
      and prior.organization_id=g.organization_id and prior.restaurant_id=g.restaurant_id
      and prior.branch_id=g.branch_id and prior.consumed_request_id=w.id
      and not prior.enabled and prior.closed_at is not null and prior.consumed_at is not null
      and w.organization_id=g.organization_id and w.restaurant_id=g.restaurant_id
      and w.branch_id=g.branch_id and w.status in ('pending','expired')
      and w.expires_at<=p_now and w.canonical_order_id is null
      and not exists(select 1 from public.web_order_decisions d where d.request_id=w.id)
      and not exists(select 1 from public.web_order_print_attempts a where a.request_id=w.id)
      and not exists(select 1 from app.storefront_manual_order_pilots x
        where x.branch_id=g.branch_id and x.consumed_request_id is not null
          and x.id not in (g.previous_pilot_id,g.pilot_id))
      and not exists(select 1 from public.web_order_requests x where x.branch_id=g.branch_id
        and x.status='pending' and x.expires_at>p_now
        and x.id is distinct from (p).consumed_request_id)
  );
$$;
revoke all on function app.manual_order_pilot_extra_allowed(app.storefront_manual_order_pilots,timestamptz)
  from public,anon,authenticated,service_role;

-- Deferred referential check keeps the future pilot and authorization atomic.
-- Direct FKs to the old audit table would intercept TRUNCATE before its
-- existing 42501 retention trigger. Both historical tables already deny
-- deletion; this immutable link verifies all references without changing that
-- existing public/private failure contract.
create function app.verify_manual_order_pilot_extra_link()
returns trigger language plpgsql set search_path='' as $$
declare v_pilot app.storefront_manual_order_pilots;
begin
  select * into v_pilot from app.storefront_manual_order_pilots where id=new.pilot_id;
  if not found or not app.manual_order_pilot_extra_allowed(v_pilot,clock_timestamp())
    or app.kitchen_print_containment_state(new.organization_id,new.restaurant_id,new.branch_id)->>'mode'
      is distinct from 'blocked' then
    raise exception 'additional allowance requires its exact linked pilot' using errcode='42501';
  end if;
  return null;
end;
$$;
revoke all on function app.verify_manual_order_pilot_extra_link()
  from public,anon,authenticated,service_role;
create constraint trigger manual_pilot_extra_allowance_link after insert
  on app.storefront_manual_order_pilot_extra_allowance deferrable initially deferred
  for each row execute function app.verify_manual_order_pilot_extra_link();

-- Keep one enabled window; permit only the separately authorized second
-- consumed row. Exact request/client identity remains globally unique.
drop index app.storefront_manual_order_pilots_one_consumed_branch;
create unique index storefront_manual_order_pilots_consumed_client
  on app.storefront_manual_order_pilots(branch_id,consumed_client_request_id)
  where consumed_request_id is not null;
create unique index storefront_manual_order_pilots_consumed_request
  on app.storefront_manual_order_pilots(consumed_request_id)
  where consumed_request_id is not null;

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
        where p.branch_id=new.branch_id and (p.enabled
          or (p.closed_at is null and p.expires_at>clock_timestamp())))
      or (exists(select 1 from app.storefront_manual_order_pilots p
        where p.branch_id=new.branch_id and p.consumed_request_id is not null)
        and not app.manual_order_pilot_extra_allowed(new,clock_timestamp())) then
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
    and (not old.enabled or (exists(select 1 from app.storefront_manual_order_pilots p
      where p.branch_id=old.branch_id and p.id<>old.id and p.consumed_request_id is not null)
      and not app.manual_order_pilot_extra_allowed(new,clock_timestamp()))) then
    raise exception 'manual pilot branch budget is already consumed or window was closed' using errcode='42501';
  end if;
  return new;
end;
$$;

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
      and (not exists(select 1 from app.storefront_manual_order_pilots prior
        where prior.branch_id=p.branch_id and prior.consumed_request_id is not null)
        or app.manual_order_pilot_extra_allowed(p,statement_timestamp()))
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

  -- Recover only the EXACT historical browser identity first. An expired old
  -- identity never consumes the separately authorized additional allowance.
  select * into v_pilot from app.storefront_manual_order_pilots
    where branch_id='2847c0be-3e31-45a5-957c-508729f1971e'
      and consumed_request_id is not null
      and consumed_client_request_id=p_client_request_id for update;
  if found then
    return app.submit_web_order_request(p_slug,p_client_request_id,p_status_token_hash,p_order);
  end if;
  select * into v_pilot from app.storefront_manual_order_pilots
    where branch_id='2847c0be-3e31-45a5-957c-508729f1971e' and enabled for update;
  if not found then return jsonb_build_object('ok',false,'error','ordering_unavailable'); end if;
  v_now:=clock_timestamp();
  if v_now<v_pilot.starts_at or v_now>=v_pilot.expires_at
     or (exists(select 1 from app.storefront_manual_order_pilots prior
       where prior.branch_id=v_pilot.branch_id and prior.consumed_request_id is not null)
       and not app.manual_order_pilot_extra_allowed(v_pilot,v_now))
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
