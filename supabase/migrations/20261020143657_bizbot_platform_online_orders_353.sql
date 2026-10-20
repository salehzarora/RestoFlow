-- BIZBOT-PLATFORM-ONLINE-ORDERS-353. Tenant-derived onboarding, not a pilot.
-- No historical dispatch, hold, decision, order or legacy lease is rewritten.
begin;

create table app.online_order_settings (
  organization_id uuid not null,
  restaurant_id uuid not null,
  branch_id uuid primary key,
  ordering_enabled boolean not null default true,
  printing_enabled boolean not null default true,
  alerts_enabled boolean not null default true,
  revision bigint not null unique default nextval('app.kitchen_print_containment_revision'),
  print_generation bigint not null,
  containment_revision bigint not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  unique(organization_id,restaurant_id,branch_id),
  foreign key(organization_id,restaurant_id,branch_id)
    references public.branches(organization_id,restaurant_id,id)
);
create table app.online_order_live_requests (
  request_id uuid primary key,
  organization_id uuid not null,
  restaurant_id uuid not null,
  branch_id uuid not null,
  print_generation bigint not null,
  admitted_at timestamptz not null default clock_timestamp(),
  foreign key(organization_id,restaurant_id,branch_id,request_id)
    references public.web_order_requests(organization_id,restaurant_id,branch_id,id),
  foreign key(organization_id,restaurant_id,branch_id)
    references app.online_order_settings(organization_id,restaurant_id,branch_id)
);
create table app.online_order_print_leases (
  request_id uuid primary key references app.online_order_live_requests(request_id),
  device_id uuid not null references public.devices(id),
  session_fingerprint text not null check(session_fingerprint ~ '^[a-f0-9]{64}$'),
  pin_session_id uuid not null references public.pin_sessions(id),
  canonical_order_id uuid not null,
  decision_id uuid not null,
  dispatch_id uuid not null unique references public.kitchen_print_dispatches(id),
  print_generation bigint not null,
  revision bigint not null unique default nextval('app.kitchen_print_containment_revision'),
  expires_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  check(expires_at>created_at and expires_at<=created_at+interval '10 minutes')
);
create index online_order_print_leases_device_idx on app.online_order_print_leases(device_id,revision desc);
create table app.pos_order_alert_branch_cursors (
  branch_id uuid primary key references public.branches(id),
  scanned_at timestamptz not null default 'epoch'
);
do $$ declare t text; begin
  foreach t in array array['online_order_settings','online_order_live_requests','online_order_print_leases',
    'pos_order_alert_branch_cursors'] loop
    execute format('alter table app.%I enable row level security',t);
    execute format('alter table app.%I force row level security',t);
    execute format('revoke all on app.%I from public,anon,authenticated,service_role',t);
    execute format('create policy deny_client on app.%I for all to authenticated using(false) with check(false)',t);
  end loop;
  foreach t in array array['online_order_live_requests','online_order_print_leases'] loop
    execute format('create trigger immutable_evidence before update or delete on app.%I for each row execute function app.enforce_audit_append_only()',t);
    execute format('create trigger immutable_evidence_no_truncate before truncate on app.%I for each statement execute function app.enforce_audit_append_only()',t);
  end loop;
end $$;

-- Pairing may precede publication. Branch configuration exists immediately,
-- while public intake still requires the separate published storefront/channel.
create function app.provision_online_order_branch(p_org uuid,p_rest uuid,p_branch uuid) returns void
language plpgsql security definer set search_path='' as $$
declare v_revision bigint; v_base jsonb;
begin
  v_base:=app.kitchen_print_containment_state(p_org,p_rest,p_branch);
  v_revision:=nextval('app.kitchen_print_containment_revision');
  insert into app.online_order_settings(organization_id,restaurant_id,branch_id,revision,print_generation,containment_revision)
  values(p_org,p_rest,p_branch,v_revision,v_revision,(v_base->>'revision')::bigint)
  on conflict(branch_id) do nothing;
  insert into app.pos_order_alert_branch_cursors(branch_id) values(p_branch) on conflict do nothing;
end; $$;
revoke all on function app.provision_online_order_branch(uuid,uuid,uuid) from public,anon,authenticated,service_role;
create function app.provision_new_branch_online_orders() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.deleted_at is null then perform app.provision_online_order_branch(new.organization_id,new.restaurant_id,new.id); end if;
  return new;
end; $$;
revoke all on function app.provision_new_branch_online_orders() from public,anon,authenticated,service_role;
create trigger provision_new_branch_online_orders after insert on public.branches
  for each row execute function app.provision_new_branch_online_orders();

-- Existing channel OFF is an explicit operational choice and is never
-- overwritten by publication or an unrelated storefront edit.
create function app.provision_storefront_online_orders() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.deleted_at is not null or not new.is_published then return new; end if;
  perform app.provision_online_order_branch(new.organization_id,new.restaurant_id,new.storefront_branch_id);
  insert into public.web_order_channel_settings(organization_id,restaurant_id,branch_id,submission_enabled)
  values(new.organization_id,new.restaurant_id,new.storefront_branch_id,true) on conflict(branch_id) do nothing;
  return new;
end; $$;
revoke all on function app.provision_storefront_online_orders() from public,anon,authenticated,service_role;
create trigger provision_storefront_online_orders after insert or update of is_published,storefront_branch_id
  on public.restaurant_storefront_profiles for each row execute function app.provision_storefront_online_orders();

-- Configuration only: existing settings are never overwritten, and no prior
-- request/dispatch is enrolled. Only published storefronts receive a channel.
select app.provision_online_order_branch(b.organization_id,b.restaurant_id,b.id)
from public.branches b where b.deleted_at is null;
insert into public.web_order_channel_settings(organization_id,restaurant_id,branch_id,submission_enabled)
select organization_id,restaurant_id,storefront_branch_id,true from public.restaurant_storefront_profiles
where is_published and deleted_at is null on conflict(branch_id) do nothing;

create function app.get_online_order_settings(p_organization_id uuid,p_restaurant_id uuid,p_branch_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v app.online_order_settings; v_rank integer;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=app.actor_rank_in_scope(p_organization_id,p_restaurant_id,p_branch_id);
  if v_rank=0 then return jsonb_build_object('ok',false,'error','not_found'); end if;
  if v_rank<2 then return jsonb_build_object('ok',false,'error','permission_denied'); end if;
  select * into v from app.online_order_settings where organization_id=p_organization_id
    and restaurant_id=p_restaurant_id and branch_id=p_branch_id;
  if not found then return jsonb_build_object('ok',true,'provisioned',false,'ordering_enabled',true,
    'printing_enabled',true,'alerts_enabled',true); end if;
  return jsonb_build_object('ok',true,'provisioned',true,'ordering_enabled',v.ordering_enabled,
    'printing_enabled',v.printing_enabled,'alerts_enabled',v.alerts_enabled,'revision',v.revision);
end; $$;
create function app.set_online_order_settings(p_organization_id uuid,p_restaurant_id uuid,p_branch_id uuid,
  p_ordering_enabled boolean,p_printing_enabled boolean,p_alerts_enabled boolean)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_old app.online_order_settings; v_revision bigint; v_base jsonb; v_rank integer;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  v_rank:=app.actor_rank_in_scope(p_organization_id,p_restaurant_id,p_branch_id);
  if v_rank=0 then return jsonb_build_object('ok',false,'error','not_found'); end if;
  if v_rank<2 then return jsonb_build_object('ok',false,'error','permission_denied'); end if;
  if p_ordering_enabled is null or p_printing_enabled is null or p_alerts_enabled is null then
    return jsonb_build_object('ok',false,'error','invalid_request'); end if;
  perform app.lock_kitchen_print_containment(p_branch_id,true);
  perform 1 from public.branches b join public.restaurants r on r.id=b.restaurant_id and r.organization_id=b.organization_id
    join public.organizations o on o.id=b.organization_id where b.id=p_branch_id and b.organization_id=p_organization_id
    and b.restaurant_id=p_restaurant_id and b.status='active' and b.deleted_at is null
    and r.status='active' and r.deleted_at is null and o.status='active' and o.deleted_at is null for share of b,r,o;
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
  select * into v_old from app.online_order_settings where branch_id=p_branch_id for update;
  v_base:=app.kitchen_print_containment_state(p_organization_id,p_restaurant_id,p_branch_id);
  v_revision:=nextval('app.kitchen_print_containment_revision');
  insert into app.online_order_settings(organization_id,restaurant_id,branch_id,ordering_enabled,printing_enabled,
    alerts_enabled,revision,print_generation,containment_revision)
  values(p_organization_id,p_restaurant_id,p_branch_id,p_ordering_enabled,p_printing_enabled,p_alerts_enabled,
    v_revision,v_revision,(v_base->>'revision')::bigint)
  on conflict(branch_id) do update set ordering_enabled=excluded.ordering_enabled,printing_enabled=excluded.printing_enabled,
    alerts_enabled=excluded.alerts_enabled,revision=excluded.revision,
    print_generation=case when app.online_order_settings.printing_enabled=excluded.printing_enabled
      and app.online_order_settings.containment_revision=excluded.containment_revision then app.online_order_settings.print_generation
      else excluded.print_generation end,containment_revision=excluded.containment_revision,updated_at=clock_timestamp();
  insert into public.web_order_channel_settings(organization_id,restaurant_id,branch_id,submission_enabled)
  values(p_organization_id,p_restaurant_id,p_branch_id,p_ordering_enabled)
  on conflict(branch_id) do update set submission_enabled=excluded.submission_enabled,updated_at=clock_timestamp();
  insert into app.pos_order_alert_branch_cursors(branch_id) values(p_branch_id) on conflict do nothing;
  insert into public.audit_events(organization_id,restaurant_id,branch_id,actor_app_user_id,action,old_values,new_values)
  values(p_organization_id,p_restaurant_id,p_branch_id,app.current_app_user_id(),'settings.online_orders.updated',
    jsonb_build_object('ordering_enabled',v_old.ordering_enabled,'printing_enabled',v_old.printing_enabled,'alerts_enabled',v_old.alerts_enabled),
    jsonb_build_object('ordering_enabled',p_ordering_enabled,'printing_enabled',p_printing_enabled,'alerts_enabled',p_alerts_enabled,'revision',v_revision));
  return app.get_online_order_settings(p_organization_id,p_restaurant_id,p_branch_id);
end; $$;
create function public.get_online_order_settings(p_organization_id uuid,p_restaurant_id uuid,p_branch_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
  select app.get_online_order_settings(p_organization_id,p_restaurant_id,p_branch_id); $$;
create function public.set_online_order_settings(p_organization_id uuid,p_restaurant_id uuid,p_branch_id uuid,
  p_ordering_enabled boolean,p_printing_enabled boolean,p_alerts_enabled boolean)
returns jsonb language sql volatile security invoker set search_path='' as $$
  select app.set_online_order_settings(p_organization_id,p_restaurant_id,p_branch_id,p_ordering_enabled,p_printing_enabled,p_alerts_enabled); $$;
revoke all on function app.get_online_order_settings(uuid,uuid,uuid),public.get_online_order_settings(uuid,uuid,uuid),
  app.set_online_order_settings(uuid,uuid,uuid,boolean,boolean,boolean),public.set_online_order_settings(uuid,uuid,uuid,boolean,boolean,boolean)
  from public,anon,authenticated,service_role;
grant execute on function app.get_online_order_settings(uuid,uuid,uuid),public.get_online_order_settings(uuid,uuid,uuid),
  app.set_online_order_settings(uuid,uuid,uuid,boolean,boolean,boolean),public.set_online_order_settings(uuid,uuid,uuid,boolean,boolean,boolean)
  to authenticated;

create function app.online_ordering_open(p_slug text) returns boolean
language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.restaurant_storefront_profiles s
    join app.online_order_settings cfg on (cfg.organization_id,cfg.restaurant_id,cfg.branch_id)=(s.organization_id,s.restaurant_id,s.storefront_branch_id)
    join public.web_order_channel_settings c on (c.organization_id,c.restaurant_id,c.branch_id)=(cfg.organization_id,cfg.restaurant_id,cfg.branch_id)
    join public.branches b on (b.organization_id,b.restaurant_id,b.id)=(cfg.organization_id,cfg.restaurant_id,cfg.branch_id)
    join public.restaurants r on (r.organization_id,r.id)=(cfg.organization_id,cfg.restaurant_id)
    join public.organizations o on o.id=cfg.organization_id
    where s.slug=p_slug and s.deleted_at is null and s.is_published and s.pickup_enabled and not s.delivery_enabled
      and (s.paused_until is null or s.paused_until<=statement_timestamp()) and cfg.ordering_enabled and c.submission_enabled
      and b.status='active' and b.deleted_at is null and r.status='active' and r.deleted_at is null
      and o.status='active' and o.deleted_at is null);
$$;
revoke all on function app.online_ordering_open(text) from public,anon,authenticated,service_role;
create or replace function public.storefront_menu(p_slug text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v jsonb;
begin
  v:=app.storefront_menu_browse_only_manual_pilot_001(p_slug);
  if v->>'ok'='true' then
    v:=jsonb_set(v,'{service,ordering_enabled}',to_jsonb(v->'service'->>'state'='open'
      and (v->'service'->>'pickup_enabled')::boolean and
      (app.online_ordering_open(p_slug) or app.mapsburger_live_ordering_open(p_slug) or app.storefront_manual_order_pilot_open(p_slug))));
  end if;
  return v;
end; $$;

create function app.submit_web_order_platform_request(p_slug text,p_client_request_id uuid,p_status_token_hash text,p_order jsonb)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_profile public.restaurant_storefront_profiles; v_cfg app.online_order_settings;
  v_result jsonb; v_request public.web_order_requests;
begin
  select * into v_profile from public.restaurant_storefront_profiles where slug=p_slug and deleted_at is null;
  if not found then return jsonb_build_object('ok',false,'error','ordering_unavailable'); end if;
  perform pg_advisory_xact_lock(hashtextextended(v_profile.restaurant_id::text||':'||p_client_request_id::text,0));
  perform app.lock_kitchen_print_containment(v_profile.storefront_branch_id,false);
  select * into v_request from public.web_order_requests where restaurant_id=v_profile.restaurant_id and client_request_id=p_client_request_id;
  if found then return app.submit_web_order_request(p_slug,p_client_request_id,p_status_token_hash,p_order); end if;
  if not app.online_ordering_open(p_slug) then return jsonb_build_object('ok',false,'error','ordering_unavailable'); end if;
  select * into strict v_cfg from app.online_order_settings where branch_id=v_profile.storefront_branch_id for share;
  v_result:=app.submit_web_order_request(p_slug,p_client_request_id,p_status_token_hash,p_order);
  if v_result->>'ok' is distinct from 'true' then return v_result; end if;
  select * into v_request from public.web_order_requests where restaurant_id=v_profile.restaurant_id
    and client_request_id=p_client_request_id and branch_id=v_profile.storefront_branch_id;
  if not found or v_result->>'replayed' is distinct from 'false' then
    raise exception 'new live request enrollment mismatch' using errcode='23514'; end if;
  insert into app.online_order_live_requests(request_id,organization_id,restaurant_id,branch_id,print_generation)
  values(v_request.id,v_request.organization_id,v_request.restaurant_id,v_request.branch_id,v_cfg.print_generation);
  return v_result;
end; $$;
create function public.submit_web_order_platform_request(p_slug text,p_client_request_id uuid,p_status_token_hash text,p_order jsonb)
returns jsonb language sql volatile security invoker set search_path='' as $$
  select app.submit_web_order_platform_request(p_slug,p_client_request_id,p_status_token_hash,p_order); $$;
revoke all on function app.submit_web_order_platform_request(text,uuid,text,jsonb),public.submit_web_order_platform_request(text,uuid,text,jsonb)
  from public,anon,authenticated,service_role;
grant execute on function app.submit_web_order_platform_request(text,uuid,text,jsonb),public.submit_web_order_platform_request(text,uuid,text,jsonb) to service_role;

-- Old enrollments retain their original evidence and resolver. Only genuinely
-- new requests cross this platform cutover, never a replay or historical row.
alter function app.pos_accept_web_order(uuid,uuid,text,uuid,uuid) rename to pos_accept_web_order_legacy_353;
revoke all on function app.pos_accept_web_order_legacy_353(uuid,uuid,text,uuid,uuid) from public,anon,authenticated,service_role;
create function app.pos_accept_web_order(p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,
  p_request_id uuid,p_decision_id uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare v_context jsonb; v_request public.web_order_requests; v_live app.online_order_live_requests;
  v_cfg app.online_order_settings; v_result jsonb; v_target public.web_order_print_attempts; v_branch uuid;
begin
  if not exists(select 1 from app.online_order_live_requests where request_id=p_request_id) then
    return app.pos_accept_web_order_legacy_353(p_pin_session_id,p_device_id,p_device_session_token,p_request_id,p_decision_id); end if;
  select ds.branch_id into v_branch from public.device_sessions ds where ds.device_id=p_device_id
    and ds.session_token_ref=app.hash_provisioning_secret(btrim(p_device_session_token))
    and ds.is_active and ds.revoked_at is null and (ds.expires_at is null or ds.expires_at>clock_timestamp());
  if v_branch is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  perform app.lock_kitchen_print_containment(v_branch,false);
  perform pg_advisory_xact_lock(hashtextextended('online-order-print-device:'||p_device_id::text,0));
  v_context:=app.pos_web_order_context(p_pin_session_id,p_device_id,p_device_session_token);
  if v_context->>'ok' is distinct from 'true' then return v_context; end if;
  select * into v_request from public.web_order_requests where id=p_request_id
    and organization_id=(v_context->>'organization_id')::uuid and restaurant_id=(v_context->>'restaurant_id')::uuid and branch_id=v_branch for update;
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
  -- Only the exact winning intent may reconcile. A different device/decision
  -- observes a conflict, rather than reporting a second successful acceptance.
  -- Neither path allocates a lease or reauthorizes an old send.
  if v_request.status='accepted' then
    if not exists(select 1 from public.web_order_decisions d where d.request_id=p_request_id
      and d.device_id=p_device_id and d.pin_session_id=p_pin_session_id and d.decision_id=p_decision_id) then
      return jsonb_build_object('ok',false,'error','decision_conflict'); end if;
    return app.decide_pos_web_order(p_pin_session_id,p_device_id,p_device_session_token,p_request_id,p_decision_id,'accepted',null);
  end if;
  v_result:=app.decide_pos_web_order(p_pin_session_id,p_device_id,p_device_session_token,p_request_id,p_decision_id,'accepted',null);
  if v_result->>'ok' is distinct from 'true' or v_result->>'replayed' is distinct from 'false' then return v_result; end if;
  select * into v_live from app.online_order_live_requests where request_id=p_request_id;
  select * into v_cfg from app.online_order_settings where branch_id=v_branch;
  select * into v_target from public.web_order_print_attempts where request_id=p_request_id;
  -- KDS has no printer-only target. Acceptance still succeeds without a printer.
  if not found then return v_result; end if;
  if not v_cfg.printing_enabled or v_live.print_generation<>v_cfg.print_generation
    or v_cfg.containment_revision<>(app.kitchen_print_containment_state(v_cfg.organization_id,v_cfg.restaurant_id,v_branch)->>'revision')::bigint then
    return v_result||jsonb_build_object('print_blocker','printing_disabled'); end if;
  if v_target.canonical_order_id::text is distinct from v_result->>'canonical_order_id'
    or v_target.decision_id::text is distinct from v_result->>'decision_id' then
    raise exception 'accepted live print enrollment mismatch' using errcode='23514'; end if;
  insert into app.online_order_print_leases(request_id,device_id,session_fingerprint,pin_session_id,canonical_order_id,
    decision_id,dispatch_id,print_generation,expires_at)
  values(p_request_id,p_device_id,encode(sha256(convert_to(p_device_session_token,'UTF8')),'hex'),p_pin_session_id,
    v_target.canonical_order_id,v_target.decision_id,v_target.dispatch_id,v_cfg.print_generation,clock_timestamp()+interval '5 minutes');
  return v_result;
end; $$;
revoke all on function app.pos_accept_web_order(uuid,uuid,text,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function app.pos_accept_web_order(uuid,uuid,text,uuid,uuid) to authenticated;

create function app.online_order_device_print_policy(p_org uuid,p_rest uuid,p_branch uuid,p_device uuid,p_session_token text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_base jsonb; v_cfg app.online_order_settings; v_lease app.online_order_print_leases;
  v_enabled boolean;
begin
  v_base:=app.mapsburger_device_print_policy(p_org,p_rest,p_branch,p_device,p_session_token);
  select * into v_cfg from app.online_order_settings where organization_id=p_org and restaurant_id=p_rest and branch_id=p_branch;
  if not found then return v_base||jsonb_build_object('web_order_printing_enabled',false); end if;
  v_enabled:=v_cfg.printing_enabled and v_cfg.containment_revision=
    (app.kitchen_print_containment_state(p_org,p_rest,p_branch)->>'revision')::bigint
    and exists(select 1 from public.devices d where d.id=p_device and d.organization_id=p_org and d.restaurant_id=p_rest
      and d.branch_id=p_branch and d.device_type='pos' and d.is_active and d.deleted_at is null);
  select * into v_lease from app.online_order_print_leases where device_id=p_device order by revision desc limit 1;
  v_base:=v_base||jsonb_build_object('web_order_printing_enabled',v_enabled,'revision',
    greatest((v_base->>'revision')::bigint,v_cfg.revision,coalesce(v_lease.revision,0)));
  if v_enabled and v_lease.print_generation=v_cfg.print_generation and v_lease.expires_at>clock_timestamp()
    and v_lease.session_fingerprint=encode(sha256(convert_to(p_session_token,'UTF8')),'hex')
    and exists(select 1 from public.web_order_print_attempts a
      join public.web_order_decisions d on d.request_id=a.request_id
      join public.web_order_requests w on w.id=a.request_id
      join app.online_order_live_requests live on live.request_id=w.id
      where a.request_id=v_lease.request_id and a.organization_id=p_org and a.restaurant_id=p_rest and a.branch_id=p_branch
        and a.canonical_order_id=v_lease.canonical_order_id and a.decision_id=v_lease.decision_id
        and a.dispatch_id=v_lease.dispatch_id and a.finished_at is null and a.attempt_id is null
        and w.status='accepted' and w.canonical_order_id=a.canonical_order_id
        and d.decision='accepted' and d.device_id=p_device and d.pin_session_id=v_lease.pin_session_id
        and d.decision_id=a.decision_id and d.canonical_order_id=a.canonical_order_id)
    and not exists(select 1 from public.kitchen_print_dispatch_holds h where h.dispatch_id=v_lease.dispatch_id) then
    return v_base||jsonb_build_object('mode','target_only','target_request_id',v_lease.request_id,'expires_at',v_lease.expires_at);
  end if;
  return v_base;
end; $$;
revoke all on function app.online_order_device_print_policy(uuid,uuid,uuid,uuid,text) from public,anon,authenticated,service_role;

-- COPIED_RUNTIME_AND_ALERT_FUNCTIONS follow (security checks retained below).
-- Unlike the compatibility latest-lease projection, this server-only resolver
-- authorizes precisely the callback request. Concurrent new accepts cannot
-- displace each other, and the additive client flag never authorizes a claim.
create function app.online_order_target_print_policy(p_org uuid,p_rest uuid,p_branch uuid,p_device uuid,
  p_session_token text,p_pin uuid,p_request uuid) returns jsonb
language plpgsql volatile security definer set search_path='' as $$
declare v_base jsonb; v_cfg app.online_order_settings; v_lease app.online_order_print_leases;
begin
  if not exists(select 1 from app.online_order_live_requests where request_id=p_request) then
    return app.mapsburger_device_print_policy(p_org,p_rest,p_branch,p_device,p_session_token); end if;
  v_base:=app.kitchen_print_containment_state(p_org,p_rest,p_branch)||jsonb_build_object('mode','blocked',
    'target_request_id',null,'expires_at',null);
  select * into v_cfg from app.online_order_settings where organization_id=p_org and restaurant_id=p_rest and branch_id=p_branch;
  select * into v_lease from app.online_order_print_leases where request_id=p_request and device_id=p_device and pin_session_id=p_pin;
  if v_cfg.printing_enabled and v_cfg.containment_revision=(v_base->>'revision')::bigint
    and v_lease.print_generation=v_cfg.print_generation and v_lease.expires_at>clock_timestamp()
    and v_lease.session_fingerprint=encode(sha256(convert_to(p_session_token,'UTF8')),'hex')
    and exists(select 1 from public.web_order_print_attempts a
      join public.web_order_decisions d on d.request_id=a.request_id
      join app.online_order_live_requests live on live.request_id=a.request_id
      where a.request_id=p_request and a.organization_id=p_org and a.restaurant_id=p_rest and a.branch_id=p_branch
        and live.organization_id=p_org and live.restaurant_id=p_rest and live.branch_id=p_branch
        and a.canonical_order_id=v_lease.canonical_order_id and a.decision_id=v_lease.decision_id
        and a.dispatch_id=v_lease.dispatch_id and a.finished_at is null and a.attempt_id is null
        and d.decision='accepted' and d.device_id=p_device and d.pin_session_id=p_pin
        and d.decision_id=a.decision_id and d.canonical_order_id=a.canonical_order_id)
    and not exists(select 1 from public.kitchen_print_dispatch_holds h where h.dispatch_id=v_lease.dispatch_id) then
    return v_base||jsonb_build_object('mode','target_only','target_request_id',p_request,'expires_at',v_lease.expires_at,
      'revision',greatest((v_base->>'revision')::bigint,v_cfg.revision,v_lease.revision));
  end if;
  return v_base;
end; $$;
revoke all on function app.online_order_target_print_policy(uuid,uuid,uuid,uuid,text,uuid,uuid) from public,anon,authenticated,service_role;

-- Existing authenticated runtime, irreversible reservation and freshness code.
create or replace function app.pos_kitchen_print_containment(p_device_id uuid,p_session_token text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_branch uuid; v_proof jsonb;
begin
  if auth.uid() is null or p_device_id is null or p_session_token is null or length(p_session_token)>4096 or btrim(p_session_token)='' then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  select ds.branch_id into v_branch from public.device_sessions ds
    where ds.device_id=p_device_id and ds.session_token_ref=app.hash_provisioning_secret(btrim(p_session_token))
      and ds.is_active and ds.revoked_at is null and (ds.expires_at is null or ds.expires_at>clock_timestamp());
  if v_branch is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  perform app.lock_kitchen_print_containment(v_branch,false);
  v_proof:=app.renew_device_session(p_device_id,p_session_token);
  if v_proof->>'ok' is distinct from 'true' or v_proof->>'device_type' is distinct from 'pos'
    or (v_proof->>'branch_id')::uuid is distinct from v_branch then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  return jsonb_build_object('ok',true,'device_id',p_device_id,'organization_id',v_proof->>'organization_id',
    'restaurant_id',v_proof->>'restaurant_id','branch_id',v_branch)
    ||app.online_order_device_print_policy((v_proof->>'organization_id')::uuid,(v_proof->>'restaurant_id')::uuid,v_branch,p_device_id,p_session_token);
end; $$;

create or replace function app.pos_web_order_print_operation(
  p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,p_request_id uuid,
  p_action text,p_attempt_id uuid default null,p_client_status text default null,p_error_code text default null
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare
  v_context jsonb;
  v_target public.web_order_print_attempts;
  v_dispatch public.kitchen_print_dispatches;
  v_now timestamptz;
  v_mode text;
  v_revision integer;
  v_readiness public.kitchen_printer_readiness_reports;
  v_result jsonb;
  v_state text;
  v_policy jsonb;
  v_scope_branch uuid;
begin
  -- Resolve the session scope without locking, then take the common branch
  -- fence BEFORE the unchanged context/hierarchy/request/dispatch lock order.
  select ds.branch_id into v_scope_branch from public.device_sessions ds
    where ds.device_id=p_device_id and ds.session_token_ref=app.hash_provisioning_secret(btrim(p_device_session_token))
      and ds.is_active and ds.revoked_at is null and (ds.expires_at is null or ds.expires_at>clock_timestamp());
  if v_scope_branch is not null then perform app.lock_kitchen_print_containment(v_scope_branch,false); end if;
  v_context:=app.pos_web_order_context(p_pin_session_id,p_device_id,p_device_session_token);
  if v_context->>'ok' is distinct from 'true' then
    return jsonb_build_object('ok',false,'error',v_context->>'error');
  end if;
  if (v_context->>'branch_id')::uuid is distinct from v_scope_branch then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  if p_request_id is null or p_action not in ('claim','begin','finish','status')
    or p_action is null or (p_action in ('begin','finish') and p_attempt_id is null)
    or (p_action='finish' and (p_client_status is null or p_client_status not in
      ('transport_accepted','possibly_printed','failed_retryable','blocked_configuration')))
    or (p_error_code is not null and p_error_code !~ '^[a-z0-9_.\-]{1,64}$') then
    return jsonb_build_object('ok',false,'error','invalid_request');
  end if;
  -- Lock order is the established hierarchy/PIN context, request, private
  -- target, dispatch. Caller supplies no order/dispatch/branch authority.
  perform 1 from public.web_order_requests w
    join public.web_order_decisions wd on wd.request_id=w.id
      and wd.organization_id=w.organization_id and wd.restaurant_id=w.restaurant_id
      and wd.branch_id=w.branch_id and wd.canonical_order_id=w.canonical_order_id
    where w.id=p_request_id and w.organization_id=(v_context->>'organization_id')::uuid
      and w.restaurant_id=(v_context->>'restaurant_id')::uuid
      and w.branch_id=(v_context->>'branch_id')::uuid
      and w.status='accepted' and wd.decision='accepted' for share of w;
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
  select * into v_target from public.web_order_print_attempts a
    where a.request_id=p_request_id and a.organization_id=(v_context->>'organization_id')::uuid
      and a.restaurant_id=(v_context->>'restaurant_id')::uuid
      and a.branch_id=(v_context->>'branch_id')::uuid for update;
  if not found then return jsonb_build_object('ok',false,'error','target_unavailable'); end if;
  select * into v_dispatch from public.kitchen_print_dispatches d
    where d.id=v_target.dispatch_id and d.organization_id=v_target.organization_id
      and d.restaurant_id=v_target.restaurant_id and d.branch_id=v_target.branch_id
      and d.order_id=v_target.canonical_order_id and d.dispatch_type='initial_order'
      and d.service_round_id is null for update;
  if not found then return jsonb_build_object('ok',false,'error','target_unavailable'); end if;
  v_now:=clock_timestamp();
  if (v_context->>'pin_expires_at')::timestamptz<=v_now
    or (v_context->>'session_expires_at')::timestamptz<=v_now then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  v_result:=jsonb_build_object('ok',true,'request_id',p_request_id,
    'canonical_order_id',v_target.canonical_order_id,'decision_id',v_target.decision_id,
    'dispatch_id',v_target.dispatch_id,'attempt_id',v_target.attempt_id,
    'printer_assignment_id',v_target.printer_assignment_id,'send_authorized',false);
  v_state:=case when v_target.outcome='transport_accepted' then 'transport_accepted'
    when v_target.attempt_id is not null then 'reconciliation_required'
    when v_dispatch.superseded_by_dispatch_id is not null then 'superseded'
    when v_target.claim_expires_at>v_now then 'claimed' else 'available' end;
  if p_action='status' then return v_result||jsonb_build_object('state',v_state); end if;
  if p_action='finish' then
    if v_target.attempt_id is distinct from p_attempt_id
      or v_target.attempt_device_id is distinct from p_device_id
      or v_target.attempt_pin_session_id is distinct from p_pin_session_id then
      return jsonb_build_object('ok',false,'error','not_attempt_owner');
    end if;
    if v_target.finished_at is not null then
      if v_target.outcome is distinct from p_client_status or v_target.error_code is distinct from p_error_code then
        return jsonb_build_object('ok',false,'error','outcome_conflict');
      end if;
      return v_result||jsonb_build_object('state',v_state,'replayed',true);
    end if;
    update public.web_order_print_attempts set outcome=p_client_status,error_code=p_error_code,
      finished_at=v_now where request_id=p_request_id;
    -- A failed native send after reservation is also permanently fenced. It
    -- may have sent zero bytes, but this contract never infers safe retransmit.
    update public.kitchen_print_dispatches set
      last_client_status=case when p_client_status='transport_accepted' then 'transport_accepted' else 'possibly_printed' end,
      last_error_code=p_error_code,
      completed_at=case when p_client_status='transport_accepted' then v_now else completed_at end,
      claim_expires_at=null,updated_at=v_now where id=v_target.dispatch_id;
    return v_result||jsonb_build_object('state',case when p_client_status='transport_accepted'
      then 'transport_accepted' else 'reconciliation_required' end,'replayed',false);
  end if;
  if v_target.attempt_id is not null then return v_result||jsonb_build_object('state',v_state); end if;
  if v_dispatch.superseded_by_dispatch_id is not null or v_dispatch.completed_at is not null
    or v_dispatch.last_client_status='possibly_printed' then
    return v_result||jsonb_build_object('state','reconciliation_required');
  end if;
  v_policy:=app.online_order_target_print_policy(v_target.organization_id,v_target.restaurant_id,v_target.branch_id,p_device_id,p_device_session_token,p_pin_session_id,p_request_id);
  if v_policy->>'mode'='blocked' or (v_policy->>'mode'='target_only'
    and (v_policy->>'target_request_id')::uuid is distinct from p_request_id)
    or exists(select 1 from public.kitchen_print_dispatch_holds h where h.dispatch_id=v_target.dispatch_id) then
    return jsonb_build_object('ok',false,'error','containment_blocked');
  end if;
  select b.kitchen_workflow_mode,b.kitchen_workflow_mode_revision into v_mode,v_revision
    from public.branches b where b.id=v_target.branch_id
      and b.organization_id=v_target.organization_id and b.restaurant_id=v_target.restaurant_id;
  if v_mode is distinct from 'printer_only' then
    return jsonb_build_object('ok',false,'error','branch_not_printer_only');
  end if;
  perform 1 from public.shifts s where s.organization_id=v_target.organization_id
    and s.restaurant_id=v_target.restaurant_id and s.branch_id=v_target.branch_id
    and s.device_id=p_device_id and s.status='open' and s.deleted_at is null for share;
  if not found then return jsonb_build_object('ok',false,'error','shift_required'); end if;
  select * into v_readiness from public.kitchen_printer_readiness_reports rr
    where rr.organization_id=v_target.organization_id and rr.restaurant_id=v_target.restaurant_id
      and rr.branch_id=v_target.branch_id and rr.device_id=p_device_id
      and rr.expires_at>clock_timestamp() and app.kitchen_readiness_report_qualifies(rr,v_revision)
    for share;
  if not found then return jsonb_build_object('ok',false,'error','readiness_required'); end if;
  -- Block assignment mutation until this reservation/claim commits, then
  -- recheck qualification and deadlines after the final possibly-blocking lock.
  perform 1 from public.printer_devices pd where pd.id=v_readiness.printer_assignment_id
    and pd.organization_id=v_target.organization_id and pd.restaurant_id=v_target.restaurant_id
    and pd.branch_id=v_target.branch_id for share;
  v_now:=clock_timestamp();
  if not app.kitchen_readiness_report_qualifies(v_readiness,v_revision)
    or v_readiness.expires_at<=v_now then
    return jsonb_build_object('ok',false,'error','readiness_required');
  end if;
  if (v_context->>'pin_expires_at')::timestamptz<=v_now
    or (v_context->>'session_expires_at')::timestamptz<=v_now then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  v_policy:=app.online_order_target_print_policy(v_target.organization_id,v_target.restaurant_id,v_target.branch_id,p_device_id,p_device_session_token,p_pin_session_id,p_request_id);
  if v_policy->>'mode'='blocked' or (v_policy->>'mode'='target_only'
    and (v_policy->>'target_request_id')::uuid is distinct from p_request_id) then
    return jsonb_build_object('ok',false,'error','containment_blocked');
  end if;
  if p_action='begin' then
    if v_target.claimed_by_device_id is distinct from p_device_id
      or v_target.claim_expires_at<=v_now or v_target.claim_expires_at is null
      or v_target.printer_assignment_id is distinct from v_readiness.printer_assignment_id
      or v_dispatch.claimed_by_device_id is distinct from p_device_id then
      return jsonb_build_object('ok',false,'error','not_claim_owner');
    end if;
    update public.web_order_print_attempts set attempt_id=p_attempt_id,attempt_device_id=p_device_id,
      attempt_pin_session_id=p_pin_session_id,attempt_reserved_at=v_now where request_id=p_request_id;
    return v_result||jsonb_build_object('state','send_reserved','send_authorized',true,
      'attempt_id',p_attempt_id,'printer_assignment_id',v_target.printer_assignment_id);
  end if;
  if v_target.claimed_by_device_id is not null and v_target.claimed_by_device_id<>p_device_id
    and v_target.claim_expires_at>v_now then
    return v_result||jsonb_build_object('state','busy');
  end if;
  update public.web_order_print_attempts set claimed_by_device_id=p_device_id,
    claim_expires_at=v_now+interval '2 minutes',printer_assignment_id=v_readiness.printer_assignment_id
    where request_id=p_request_id;
  update public.kitchen_print_dispatches set claimed_at=v_now,claimed_by_device_id=p_device_id,
    claim_expires_at=v_now+interval '2 minutes',updated_at=v_now where id=v_target.dispatch_id;
  return v_result||jsonb_build_object('state','claimed','printer_assignment_id',v_readiness.printer_assignment_id,
    'dispatch',jsonb_build_object('id',v_dispatch.id,'dispatch_type',v_dispatch.dispatch_type,
      'order_id',v_dispatch.order_id,'service_round_id',v_dispatch.service_round_id,
      'payload_version',v_dispatch.payload_version,'payload',v_dispatch.money_free_payload,
      'created_at',v_dispatch.created_at,'claim_expires_at',v_now+interval '2 minutes'));
end; $$;

-- Tenant identity is derived from the authenticated context, never a UUID list.
alter table app.pos_order_alert_registrations drop constraint pos_order_alert_registrations_check;

create or replace function app.pos_order_alert_authority(p_registration app.pos_order_alert_registrations)
returns timestamptz language sql stable security definer set search_path='' as $$
 select least(p_registration.authority_expires_at,ds.expires_at,ps.expires_at)
 from public.device_sessions ds
 join public.devices d on d.id=ds.device_id and d.organization_id=ds.organization_id
   and d.restaurant_id=ds.restaurant_id and d.branch_id=ds.branch_id
 join public.device_pairings dp on dp.id=ds.device_pairing_id and dp.device_id=d.id
   and dp.organization_id=ds.organization_id and dp.restaurant_id=ds.restaurant_id and dp.branch_id=ds.branch_id
 join public.pin_sessions ps on ps.id=p_registration.pin_session_id and ps.device_session_id=ds.id
   and ps.organization_id=ds.organization_id and ps.restaurant_id=ds.restaurant_id and ps.branch_id=ds.branch_id
 join public.employee_profiles ep on ep.id=ps.employee_profile_id and ep.organization_id=ds.organization_id
 join public.memberships m on m.id=ps.resolved_membership_id and m.organization_id=ds.organization_id
 join public.organizations o on o.id=ds.organization_id
 join public.restaurants r on r.id=ds.restaurant_id and r.organization_id=o.id
 join public.branches b on b.id=ds.branch_id and b.restaurant_id=r.id and b.organization_id=o.id
 join app.pos_order_alert_settings s on s.revision=p_registration.setting_revision
 where p_registration.enabled and p_registration.authority_expires_at>statement_timestamp()
   and s.enabled and s.revision=(select max(revision) from app.pos_order_alert_settings)
   and ds.id=p_registration.device_session_id and d.id=p_registration.device_id
   and ps.employee_profile_id=p_registration.employee_profile_id and ps.resolved_membership_id=p_registration.resolved_membership_id
   and ds.is_active and ds.revoked_at is null and ds.expires_at>statement_timestamp()
   and d.device_type='pos' and d.is_active and d.deleted_at is null
   and dp.status='active' and dp.revoked_at is null and dp.deleted_at is null
   and ps.is_active and ps.ended_at is null and ps.expires_at>statement_timestamp()
   and ep.employment_status='active' and ep.deleted_at is null
   and (ep.restaurant_id is null or ep.restaurant_id=ds.restaurant_id)
   and (ep.branch_id is null or ep.branch_id=ds.branch_id)
   and m.status='active' and m.deleted_at is null
   and (m.restaurant_id is null or m.restaurant_id=ds.restaurant_id)
   and (m.branch_id is null or m.branch_id=ds.branch_id)
   and m.role in ('cashier','manager','restaurant_owner','org_owner')
   and (ep.membership_id=m.id or (ep.membership_id is null and ep.app_user_id=m.app_user_id
     and (select count(*) from public.memberships mm where mm.organization_id=ds.organization_id
       and mm.app_user_id=ep.app_user_id and mm.status='active' and mm.deleted_at is null)=1))
   and o.status='active' and o.deleted_at is null and r.status='active' and r.deleted_at is null
   and b.status='active' and b.deleted_at is null
   and exists(select 1 from app.online_order_settings cfg where cfg.organization_id=ds.organization_id
     and cfg.restaurant_id=ds.restaurant_id and cfg.branch_id=ds.branch_id and cfg.alerts_enabled);
$$;

create or replace function app.pos_register_order_alert(p_installation_id uuid,p_fcm_token text,p_status_secret text,
  p_device_id uuid,p_pin_session_id uuid,p_device_session_token text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_context jsonb; v_setting app.pos_order_alert_settings; v_registration app.pos_order_alert_registrations;
  v_now timestamptz; v_deadline timestamptz; v_hash text;
begin
  if p_installation_id is null or p_status_secret is null or p_status_secret !~ '^[0-9a-f]{64}$'
    or p_fcm_token is null or length(p_fcm_token) not between 20 and 4096 or p_fcm_token ~ '[[:space:][:cntrl:]]' then
    return jsonb_build_object('ok',false,'error','invalid_request'); end if;
  v_context:=app.pos_web_order_context(p_pin_session_id,p_device_id,p_device_session_token);
  if v_context->>'ok' is distinct from 'true' then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  if not exists(select 1 from app.online_order_settings cfg where cfg.organization_id=(v_context->>'organization_id')::uuid
    and cfg.restaurant_id=(v_context->>'restaurant_id')::uuid and cfg.branch_id=(v_context->>'branch_id')::uuid
    and cfg.alerts_enabled) then return jsonb_build_object('ok',false,'error','disabled'); end if;
  -- Registration is foreground authenticated activity; authority cannot be
  -- extended by the delegated native status capability.
  select * into v_setting from app.pos_order_alert_settings order by revision desc limit 1 for share;
  if not found or not v_setting.enabled then return jsonb_build_object('ok',false,'error','disabled'); end if;
  v_now:=clock_timestamp();
  v_deadline:=least(v_now+interval '8 hours',(v_context->>'pin_expires_at')::timestamptz,
    (v_context->>'session_expires_at')::timestamptz);
  if v_context->>'pin_expires_at' is null or v_context->>'session_expires_at' is null or v_deadline<=v_now then
    return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  v_hash:=encode(sha256(convert_to(p_fcm_token,'UTF8')),'hex');
  if exists(select 1 from app.pos_order_alert_registrations where installation_id=p_installation_id and device_id<>p_device_id)
    or exists(select 1 from app.pos_order_alert_registrations where enabled and token_hash=v_hash and device_id<>p_device_id) then
    return jsonb_build_object('ok',false,'error','invalid_request'); end if;
  update app.pos_order_alert_registrations set enabled=false where device_id=p_device_id and enabled;
  insert into app.pos_order_alert_registrations(installation_id,setting_revision,organization_id,restaurant_id,branch_id,
    device_id,device_session_id,pin_session_id,employee_profile_id,resolved_membership_id,fcm_token,token_hash,
    status_secret_hash,registered_at,refreshed_at,authority_expires_at)
  values(p_installation_id,v_setting.revision,(v_context->>'organization_id')::uuid,(v_context->>'restaurant_id')::uuid,
    (v_context->>'branch_id')::uuid,p_device_id,(v_context->>'device_session_id')::uuid,p_pin_session_id,
    (v_context->>'employee_profile_id')::uuid,(v_context->>'resolved_membership_id')::uuid,p_fcm_token,v_hash,
    encode(sha256(convert_to(p_status_secret,'UTF8')),'hex'),v_now,v_now,v_deadline)
  -- Every real foreground renewal fences older native refresh requests,
  -- including a renewal carrying the same SDK token and status capability.
  on conflict(installation_id) do update set generation=gen_random_uuid(),
    setting_revision=excluded.setting_revision,
    device_session_id=excluded.device_session_id,pin_session_id=excluded.pin_session_id,
    employee_profile_id=excluded.employee_profile_id,resolved_membership_id=excluded.resolved_membership_id,
    fcm_token=excluded.fcm_token,token_hash=excluded.token_hash,status_secret_hash=excluded.status_secret_hash,
    enabled=true,registered_at=case when app.pos_order_alert_registrations.fcm_token=excluded.fcm_token
      and app.pos_order_alert_registrations.status_secret_hash=excluded.status_secret_hash
      and app.pos_order_alert_registrations.pin_session_id=excluded.pin_session_id
      and app.pos_order_alert_registrations.device_session_id=excluded.device_session_id
      and app.pos_order_alert_registrations.setting_revision=excluded.setting_revision
      then app.pos_order_alert_registrations.registered_at else excluded.registered_at end,
    refreshed_at=excluded.refreshed_at,authority_expires_at=excluded.authority_expires_at
  where app.pos_order_alert_registrations.device_id=excluded.device_id returning * into v_registration;
  if not found then raise exception 'installation scope changed' using errcode='42501'; end if;
  return jsonb_build_object('ok',true,'registration_id',v_registration.id,'generation',v_registration.generation,'authority_expires_at',v_deadline);
end; $$;

create view app.online_order_notification_requests as
 select request_id from app.online_order_live_requests
 union select request_id from app.mapsburger_live_web_requests;
revoke all on app.online_order_notification_requests from public,anon,authenticated,service_role;

create or replace function app.pos_order_alert_status(p_installation_id uuid,p_status_secret_hash text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_registration app.pos_order_alert_registrations; v_deadline timestamptz; v_now timestamptz:=statement_timestamp(); v_rows jsonb;
begin
  if p_status_secret_hash is null or p_status_secret_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok',false,'error','unauthorized'); end if;
  select * into v_registration from app.pos_order_alert_registrations where installation_id=p_installation_id
    and status_secret_hash=p_status_secret_hash;
  if not found then return jsonb_build_object('ok',false,'error','unauthorized'); end if;
  v_deadline:=app.pos_order_alert_authority(v_registration);
  if v_deadline is null then return jsonb_build_object('ok',false,'error','unauthorized'); end if;
  select coalesce(jsonb_agg(jsonb_build_object('request_id',q.id,'expires_at',q.expires_at) order by q.created_at,q.id),'[]')
    into v_rows from(select w.id,w.expires_at,w.created_at from public.web_order_requests w
      join app.online_order_notification_requests live on live.request_id=w.id
      join app.pos_order_alert_settings s on s.revision=v_registration.setting_revision
      where w.organization_id=v_registration.organization_id and w.restaurant_id=v_registration.restaurant_id
        and w.branch_id=v_registration.branch_id and w.status='pending' and w.expires_at>v_now
        and w.created_at>=s.created_at order by w.created_at,w.id limit 51) q;
  if jsonb_array_length(v_rows)>50 then return jsonb_build_object('ok',false,'error','capacity_exceeded'); end if;
  return jsonb_build_object('ok',true,'server_time',v_now,'registration_id',v_registration.id,'authority_expires_at',v_deadline,'requests',v_rows);
end; $$;

alter table app.pos_order_alert_registrations
  add constraint pos_order_alert_device_scope foreign key(organization_id,restaurant_id,branch_id,device_id)
    references public.devices(organization_id,restaurant_id,branch_id,id),
  add constraint pos_order_alert_session_scope foreign key(organization_id,restaurant_id,branch_id,device_session_id)
    references public.device_sessions(organization_id,restaurant_id,branch_id,id),
  add constraint pos_order_alert_pin_scope foreign key(organization_id,restaurant_id,branch_id,pin_session_id)
    references public.pin_sessions(organization_id,restaurant_id,branch_id,id);
create index pos_order_alert_registration_branch_idx on app.pos_order_alert_registrations(branch_id) where enabled;

-- Server-only native token rotation. The existing status capability can change
-- token routing, never extend employee/PIN/device/setting authority or enable it.
create function app.pos_refresh_order_alert_token(p_installation_id uuid,p_status_secret_hash text,p_fcm_token text,p_expected_generation uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_registration app.pos_order_alert_registrations; v_deadline timestamptz; v_hash text;
begin
  if p_expected_generation is null or p_status_secret_hash is null or p_status_secret_hash !~ '^[0-9a-f]{64}$'
    or p_fcm_token is null or length(p_fcm_token) not between 20 and 4096 or p_fcm_token ~ '[[:space:][:cntrl:]]' then
    return jsonb_build_object('ok',false,'error','unauthorized'); end if;
  select * into v_registration from app.pos_order_alert_registrations where installation_id=p_installation_id
    and status_secret_hash=p_status_secret_hash and generation=p_expected_generation for update;
  if not found then return jsonb_build_object('ok',false,'error','unauthorized'); end if;
  v_deadline:=app.pos_order_alert_authority(v_registration);
  if v_deadline is null then return jsonb_build_object('ok',false,'error','unauthorized'); end if;
  v_hash:=encode(sha256(convert_to(p_fcm_token,'UTF8')),'hex');
  if exists(select 1 from app.pos_order_alert_registrations where enabled and token_hash=v_hash and id<>v_registration.id) then
    return jsonb_build_object('ok',false,'error','unauthorized'); end if;
  begin
    update app.pos_order_alert_registrations set fcm_token=p_fcm_token,token_hash=v_hash,
      generation=case when fcm_token=p_fcm_token then generation else gen_random_uuid() end where id=v_registration.id
      returning * into v_registration;
  exception when unique_violation then return jsonb_build_object('ok',false,'error','unauthorized'); end;
  return jsonb_build_object('ok',true,'registration_id',v_registration.id,'generation',v_registration.generation,
    'server_time',clock_timestamp(),'authority_expires_at',v_deadline);
end; $$;
create function public.pos_refresh_order_alert_token(p_installation_id uuid,p_status_secret_hash text,p_fcm_token text,p_expected_generation uuid)
returns jsonb language sql volatile security invoker set search_path='' as $$
  select app.pos_refresh_order_alert_token(p_installation_id,p_status_secret_hash,p_fcm_token,p_expected_generation); $$;
revoke all on function app.pos_refresh_order_alert_token(uuid,text,text,uuid),public.pos_refresh_order_alert_token(uuid,text,text,uuid)
  from public,anon,authenticated,service_role;
grant execute on function app.pos_refresh_order_alert_token(uuid,text,text,uuid),public.pos_refresh_order_alert_token(uuid,text,text,uuid) to service_role;

create or replace function app.pos_claim_order_alert_deliveries(p_limit integer default 10)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_now timestamptz:=clock_timestamp(); v_rows jsonb; v_branches uuid[];
begin
  if p_limit is null or p_limit not between 1 and 10 then return jsonb_build_object('ok',false,'error','invalid_request'); end if;
  if not coalesce((select enabled from app.pos_order_alert_settings order by revision desc limit 1),false) then
    return jsonb_build_object('ok',true,'server_time',v_now,'deliveries','[]'::jsonb); end if;
  -- Idle tenants are excluded from election. Least recently scanned *busy*
  -- branches rotate, and SKIP LOCKED prevents an overlapping worker from
  -- spending a second batch on the same branch during this transaction.
  select coalesce(array_agg(q.branch_id),'{}'::uuid[]) into v_branches from (
    select c.branch_id from app.pos_order_alert_branch_cursors c where exists(
      select 1 from app.pos_order_alert_registrations r where r.branch_id=c.branch_id
      and app.pos_order_alert_authority(r)>v_now and (
        exists(select 1 from public.web_order_requests w
          join app.online_order_notification_requests live on live.request_id=w.id
          join app.pos_order_alert_settings s on s.revision=r.setting_revision
          where w.organization_id=r.organization_id and w.restaurant_id=r.restaurant_id and w.branch_id=r.branch_id
            and w.status='pending' and w.expires_at>v_now and w.created_at>=r.registered_at and w.created_at>=s.created_at
            and not exists(select 1 from app.pos_order_alert_deliveries d where d.registration_id=r.id
              and d.generation=r.generation and d.request_id=w.id and d.kind='pending'))
        or exists(select 1 from app.pos_order_alert_deliveries d join public.web_order_requests w on w.id=d.request_id
          where d.registration_id=r.id and d.generation=r.generation and (
            (d.state in ('queued','leased') and d.next_attempt_at<=v_now and d.attempt_count<3
              and (d.lease_until is null or d.lease_until<=v_now))
            or (d.kind='pending' and (w.expires_at<=v_now or exists(select 1 from public.web_order_decisions dec where dec.request_id=w.id))
              and not exists(select 1 from app.pos_order_alert_deliveries term where term.registration_id=d.registration_id
                and term.generation=d.generation and term.request_id=d.request_id and term.kind='terminal'))))))
      order by c.scanned_at,c.branch_id for update of c skip locked limit 10) q;
  update app.pos_order_alert_branch_cursors set scanned_at=v_now where branch_id=any(v_branches);

  -- At most 100 new pending rows (10 busy branches x 10) plus 100 terminal
  -- rows per call: 200 total independent of tenant count. Claims remain <=10.
  -- Existing uniqueness is the fanout backstop.
  insert into app.pos_order_alert_deliveries(registration_id,generation,request_id,kind)
  select q.registration_id,q.generation,q.request_id,'pending' from unnest(v_branches) b(branch_id)
  cross join lateral(select r.id registration_id,r.generation,w.id request_id
    from app.pos_order_alert_registrations r join public.web_order_requests w
      on w.organization_id=r.organization_id and w.restaurant_id=r.restaurant_id and w.branch_id=r.branch_id
    join public.web_order_request_events e on e.request_id=w.id and e.event_type='received'
    join app.online_order_notification_requests live on live.request_id=w.id
    join app.pos_order_alert_settings s on s.revision=r.setting_revision
    where r.branch_id=b.branch_id and app.pos_order_alert_authority(r)>v_now
      and w.created_at>=s.created_at and w.created_at>=r.registered_at and w.status='pending' and w.expires_at>v_now
      and not exists(select 1 from app.pos_order_alert_deliveries d where d.registration_id=r.id
        and d.generation=r.generation and d.request_id=w.id and d.kind='pending')
    order by w.created_at,w.id,r.id limit 10) q on conflict do nothing;
  insert into app.pos_order_alert_deliveries(registration_id,generation,request_id,kind)
  select d.registration_id,d.generation,d.request_id,'terminal' from app.pos_order_alert_deliveries d
    join app.pos_order_alert_registrations r on r.id=d.registration_id and r.generation=d.generation
    join public.web_order_requests w on w.id=d.request_id
    where r.branch_id=any(v_branches) and d.kind='pending' and app.pos_order_alert_authority(r)>v_now
      and (w.expires_at<=v_now or exists(select 1 from public.web_order_decisions dec where dec.request_id=w.id))
      and not exists(select 1 from app.pos_order_alert_deliveries term where term.registration_id=d.registration_id
        and term.generation=d.generation and term.request_id=d.request_id and term.kind='terminal')
    order by d.created_at,d.id limit 100 on conflict do nothing;
  with stale as(select d.id from app.pos_order_alert_deliveries d
    join app.pos_order_alert_registrations r on r.id=d.registration_id join public.web_order_requests w on w.id=d.request_id
    where d.state in ('queued','leased') and (r.generation<>d.generation or app.pos_order_alert_authority(r) is null
      or (d.attempt_count>=3 and (d.lease_until is null or d.lease_until<=v_now))
      or (d.kind='pending' and (w.status<>'pending' or w.expires_at<=v_now)))
    order by d.created_at,d.id for update of d skip locked limit 100)
  update app.pos_order_alert_deliveries d set state='abandoned',lease_id=null,lease_until=null from stale s where s.id=d.id;
  with branch_candidates as (
    select q.id,q.created_at,row_number() over(partition by b.branch_id order by q.created_at,q.id) tenant_position
    from unnest(v_branches) b(branch_id) cross join lateral(
      select d.id,d.created_at from app.pos_order_alert_deliveries d
      join app.pos_order_alert_registrations r on r.id=d.registration_id and r.generation=d.generation
      join public.web_order_requests w on w.id=d.request_id
      where r.branch_id=b.branch_id and d.state in ('queued','leased') and d.next_attempt_at<=v_now and d.attempt_count<3
        and (d.lease_until is null or d.lease_until<=v_now) and app.pos_order_alert_authority(r)>v_now
        and (d.kind='terminal' or (w.status='pending' and w.expires_at>v_now))
      order by d.created_at,d.id for update of d skip locked limit 10) q
  ), candidates as(select id from branch_candidates order by tenant_position,created_at,id limit p_limit), leased as (
    update app.pos_order_alert_deliveries d set state='leased',attempt_count=d.attempt_count+1,
      lease_id=gen_random_uuid(),lease_until=v_now+interval '2 minutes'
    from candidates c where d.id=c.id returning d.*
  ) select coalesce(jsonb_agg(jsonb_build_object('delivery_id',l.id,'lease_id',l.lease_id,'registration_id',r.id,
    'generation',l.generation,'fcm_token',r.fcm_token,'kind',l.kind,'request_id',l.request_id,
    'expires_at',w.expires_at,'authority_expires_at',app.pos_order_alert_authority(r))),'[]') into v_rows
    from leased l join app.pos_order_alert_registrations r on r.id=l.registration_id join public.web_order_requests w on w.id=l.request_id;
  return jsonb_build_object('ok',true,'server_time',v_now,'deliveries',v_rows);
end; $$;

commit;
