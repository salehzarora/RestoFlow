-- BIZBOT-STOREFRONT-MANUAL-ORDER-PILOT-001: ONE replacement window after
-- an additional allowance was closed WITHOUT creating a request. Default OFF.
-- Does not rearm, extend, rewrite or delete any existing authorization/window.
begin;

create table app.storefront_manual_order_pilot_unused_retry (
  singleton boolean primary key default true check (singleton),
  pilot_id uuid not null unique,
  unused_extra_pilot_id uuid not null unique,
  organization_id uuid not null,
  restaurant_id uuid not null,
  branch_id uuid not null,
  starts_at timestamptz not null,
  expires_at timestamptz not null,
  operator_reference text not null check (length(operator_reference) between 1 and 240),
  authorized_at timestamptz not null default clock_timestamp(),
  check (pilot_id<>unused_extra_pilot_id),
  check (isfinite(starts_at) and isfinite(expires_at) and expires_at>starts_at
    and expires_at-starts_at<=interval '15 minutes'),
  check (organization_id='20605c2b-3145-4803-a990-bbec3d9c1096'::uuid
    and restaurant_id='de3bbc64-edad-4ff4-bccd-c2ef217c1d56'::uuid
    and branch_id='2847c0be-3e31-45a5-957c-508729f1971e'::uuid),
  foreign key (organization_id,restaurant_id,branch_id)
    references public.branches(organization_id,restaurant_id,id)
);
alter table app.storefront_manual_order_pilot_unused_retry enable row level security;
alter table app.storefront_manual_order_pilot_unused_retry force row level security;
revoke all on app.storefront_manual_order_pilot_unused_retry
  from public,anon,authenticated,service_role;

-- The original additional-success budget is transferred to one exact future
-- window only while the previous extra window is closed and wholly unconsumed.
-- Retain all prior expiry, identity, pending, decision and canonical checks.
create or replace function app.manual_order_pilot_extra_allowed(
  p app.storefront_manual_order_pilots,p_now timestamptz
) returns boolean language sql stable set search_path='' as $$
  with candidates as (
    select g.pilot_id,g.previous_pilot_id,g.previous_request_id,
      g.organization_id,g.restaurant_id,g.branch_id,g.starts_at,g.expires_at,
      g.operator_reference,null::text contact_salt,null::text contact_hash
    from app.storefront_manual_order_pilot_extra_allowance g
    union all
    select r.pilot_id,g.previous_pilot_id,g.previous_request_id,
      r.organization_id,r.restaurant_id,r.branch_id,r.starts_at,r.expires_at,
      r.operator_reference,unused.contact_salt,unused.contact_hash
    from app.storefront_manual_order_pilot_unused_retry r
    join app.storefront_manual_order_pilot_extra_allowance g
      on g.pilot_id=r.unused_extra_pilot_id
      and g.organization_id=r.organization_id and g.restaurant_id=r.restaurant_id
      and g.branch_id=r.branch_id
    join app.storefront_manual_order_pilots unused on unused.id=g.pilot_id
      and unused.organization_id=g.organization_id and unused.restaurant_id=g.restaurant_id
      and unused.branch_id=g.branch_id and unused.starts_at=g.starts_at
      and unused.expires_at=g.expires_at and unused.operator_reference=g.operator_reference
    where not unused.enabled and unused.closed_at is not null
      and unused.consumed_client_request_id is null and unused.consumed_request_id is null
      and unused.consumed_at is null
  )
  select exists (
    select 1 from candidates g
    join app.storefront_manual_order_pilots prior on prior.id=g.previous_pilot_id
    join public.web_order_requests w on w.id=g.previous_request_id
    where g.pilot_id=(p).id and g.organization_id=(p).organization_id
      and g.restaurant_id=(p).restaurant_id and g.branch_id=(p).branch_id
      and g.starts_at=(p).starts_at and g.expires_at=(p).expires_at
      and g.operator_reference=(p).operator_reference and p_now<g.expires_at
      and (g.contact_hash is null or
        ((p).contact_salt=g.contact_salt and (p).contact_hash=g.contact_hash))
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

create function app.guard_manual_order_pilot_unused_retry()
returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op<>'INSERT' then
    raise exception 'unused pilot retry authorization is immutable' using errcode='42501';
  end if;
  perform app.lock_kitchen_print_containment(new.branch_id,true);
  if new.expires_at<=clock_timestamp() or new.starts_at>clock_timestamp()+interval '1 minute'
    or exists(select 1 from app.storefront_manual_order_pilots p
      where p.id=new.pilot_id or (p.branch_id=new.branch_id and p.enabled))
    or not exists (
      select 1 from app.storefront_manual_order_pilot_extra_allowance g
      join app.storefront_manual_order_pilots unused on unused.id=g.pilot_id
      join app.storefront_manual_order_pilots prior on prior.id=g.previous_pilot_id
      join public.web_order_requests w on w.id=g.previous_request_id
      where g.pilot_id=new.unused_extra_pilot_id and g.organization_id=new.organization_id
        and g.restaurant_id=new.restaurant_id and g.branch_id=new.branch_id
        and unused.organization_id=g.organization_id and unused.restaurant_id=g.restaurant_id
        and unused.branch_id=g.branch_id and unused.starts_at=g.starts_at
        and unused.expires_at=g.expires_at and unused.operator_reference=g.operator_reference
        and not unused.enabled and unused.closed_at is not null
        and unused.consumed_client_request_id is null and unused.consumed_request_id is null
        and unused.consumed_at is null
        and prior.organization_id=g.organization_id and prior.restaurant_id=g.restaurant_id
        and prior.branch_id=g.branch_id and prior.consumed_request_id=w.id
        and not prior.enabled and prior.closed_at is not null and prior.consumed_at is not null
        and w.organization_id=g.organization_id and w.restaurant_id=g.restaurant_id
        and w.branch_id=g.branch_id and w.status in ('pending','expired')
        and w.expires_at<=clock_timestamp() and w.canonical_order_id is null
        and not exists(select 1 from public.web_order_decisions d where d.request_id=w.id)
        and not exists(select 1 from public.web_order_print_attempts a where a.request_id=w.id)
        and not exists(select 1 from app.storefront_manual_order_pilots x
          where x.branch_id=g.branch_id and x.consumed_request_id is not null
            and x.id<>g.previous_pilot_id)
    )
    or exists(select 1 from public.web_order_requests w where w.branch_id=new.branch_id
      and w.status='pending' and w.expires_at>clock_timestamp())
    or app.kitchen_print_containment_state(new.organization_id,new.restaurant_id,new.branch_id)->>'mode'
      is distinct from 'blocked' then
    raise exception 'unused retry authorization prerequisites not satisfied' using errcode='42501';
  end if;
  return new;
end;
$$;
revoke all on function app.guard_manual_order_pilot_unused_retry()
  from public,anon,authenticated,service_role;
create trigger manual_pilot_unused_retry_guard before insert or update or delete
  on app.storefront_manual_order_pilot_unused_retry for each row
  execute function app.guard_manual_order_pilot_unused_retry();
create trigger manual_pilot_unused_retry_no_truncate before truncate
  on app.storefront_manual_order_pilot_unused_retry for each statement
  execute function app.guard_manual_order_pilot_unused_retry();

-- Avoid changing existing audit-table TRUNCATE/retention behavior with FKs.
-- The new authorization and exact future pilot must commit together instead.
create function app.verify_manual_order_pilot_unused_retry_link()
returns trigger language plpgsql set search_path='' as $$
declare v_pilot app.storefront_manual_order_pilots;
begin
  select * into v_pilot from app.storefront_manual_order_pilots where id=new.pilot_id;
  if not found or not v_pilot.enabled or v_pilot.closed_at is not null
    or v_pilot.consumed_request_id is not null
    or not app.manual_order_pilot_extra_allowed(v_pilot,clock_timestamp())
    or app.kitchen_print_containment_state(new.organization_id,new.restaurant_id,new.branch_id)->>'mode'
      is distinct from 'blocked' then
    raise exception 'unused retry requires its exact linked pilot' using errcode='42501';
  end if;
  return null;
end;
$$;
revoke all on function app.verify_manual_order_pilot_unused_retry_link()
  from public,anon,authenticated,service_role;
create constraint trigger manual_pilot_unused_retry_link after insert
  on app.storefront_manual_order_pilot_unused_retry deferrable initially deferred
  for each row execute function app.verify_manual_order_pilot_unused_retry_link();

commit;
