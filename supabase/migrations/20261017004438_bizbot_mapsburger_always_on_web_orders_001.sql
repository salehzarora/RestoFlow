-- BIZBOT-MAPSBURGER-ALWAYS-ON-WEB-ORDERS-001. Capability only; default OFF.
-- No profile, channel, policy, hold, historical request or dispatch is changed.
begin;

create table app.mapsburger_web_order_rollouts (
  revision bigint primary key default nextval('app.kitchen_print_containment_revision'),
  organization_id uuid not null default '20605c2b-3145-4803-a990-bbec3d9c1096',
  restaurant_id uuid not null default 'de3bbc64-edad-4ff4-bccd-c2ef217c1d56',
  branch_id uuid not null default '2847c0be-3e31-45a5-957c-508729f1971e',
  intake_enabled boolean not null default false,
  print_enabled boolean not null default false,
  print_generation bigint not null,
  allowed_device_ids uuid[] not null,
  containment_revision bigint not null,
  admission_cutoff timestamptz not null,
  reason text not null check(length(btrim(reason)) between 1 and 500),
  operator_reference text not null check(length(btrim(operator_reference)) between 1 and 200),
  recorded_at timestamptz not null default clock_timestamp(),
  recorded_by text not null default session_user,
  check(organization_id='20605c2b-3145-4803-a990-bbec3d9c1096'::uuid
    and restaurant_id='de3bbc64-edad-4ff4-bccd-c2ef217c1d56'::uuid
    and branch_id='2847c0be-3e31-45a5-957c-508729f1971e'::uuid),
  check(cardinality(allowed_device_ids) between 1 and 20),
  check(not intake_enabled or print_enabled),
  foreign key(organization_id,restaurant_id,branch_id)
    references public.branches(organization_id,restaurant_id,id)
);

-- A trusted NEW live submission is enrolled in the same transaction as the
-- pending request. Neither a timestamp guess nor an old acceptance can enroll.
create table app.mapsburger_live_web_requests (
  request_id uuid primary key references public.web_order_requests(id),
  rollout_revision bigint not null references app.mapsburger_web_order_rollouts(revision),
  print_generation bigint not null,
  admitted_at timestamptz not null default clock_timestamp()
);

-- One exact request lease per accepted callback, NEVER a rolling oldest/newest
-- request selection. A device cannot accept a different live request while its
-- previous callback is unresolved. Terminal/expired lease identities remain.
create table app.mapsburger_web_print_leases (
  request_id uuid primary key references app.mapsburger_live_web_requests(request_id),
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
create index mapsburger_web_print_leases_device_idx
  on app.mapsburger_web_print_leases(device_id,revision desc);
create table app.mapsburger_web_print_lease_closures (
  request_id uuid primary key references app.mapsburger_web_print_leases(request_id),
  revision bigint not null unique default nextval('app.kitchen_print_containment_revision'),
  reason text not null check(reason in ('expired_before_send','terminal_attempt')),
  recorded_at timestamptz not null default clock_timestamp()
);

create function app.guard_mapsburger_web_order_evidence() returns trigger
language plpgsql set search_path='' as $$
begin
  raise exception 'Maps Burger rollout evidence is append-only' using errcode='42501';
end; $$;
revoke all on function app.guard_mapsburger_web_order_evidence() from public,anon,authenticated,service_role;
do $$ declare t text; begin
  foreach t in array array['mapsburger_web_order_rollouts','mapsburger_live_web_requests',
    'mapsburger_web_print_leases','mapsburger_web_print_lease_closures'] loop
    execute format('alter table app.%I enable row level security',t);
    execute format('alter table app.%I force row level security',t);
    execute format('revoke all on app.%I from public,anon,authenticated,service_role',t);
    execute format('create trigger immutable_evidence before update or delete on app.%I for each row execute function app.guard_mapsburger_web_order_evidence()',t);
    execute format('create trigger immutable_evidence_no_truncate before truncate on app.%I for each statement execute function app.guard_mapsburger_web_order_evidence()',t);
  end loop;
end $$;

-- Privileged operator API only. The exclusive branch fence orders OFF with
-- submissions/acceptance/begin. No application or service role can activate it.
-- Intake OFF preserves pending/status and existing print eligibility. Emergency
-- print OFF revokes leases; re-enabling creates a new generation, never reviving
-- an old request. Neither action acknowledges or changes a dispatch outcome.
create function app.set_mapsburger_web_orders(
  p_intake_enabled boolean,p_print_enabled boolean,p_allowed_device_ids uuid[],
  p_reason text,p_operator_reference text
) returns bigint language plpgsql volatile set search_path='' as $$
declare
  v_previous app.mapsburger_web_order_rollouts; v_revision bigint; v_generation bigint;
  v_state jsonb; v_cutoff timestamptz; v_devices uuid[];
begin
  perform app.lock_kitchen_print_containment('2847c0be-3e31-45a5-957c-508729f1971e',true);
  select * into v_previous from app.mapsburger_web_order_rollouts order by revision desc limit 1;
  select array_agg(distinct d order by d) into v_devices from unnest(p_allowed_device_ids) d;
  if p_intake_enabled is null or p_print_enabled is null or v_devices is null
    or cardinality(v_devices) not between 1 and 20 or array_position(v_devices,null) is not null
    or (p_intake_enabled and not p_print_enabled) then
    raise exception 'invalid rollout configuration' using errcode='22023';
  end if;
  v_state:=app.kitchen_print_containment_state('20605c2b-3145-4803-a990-bbec3d9c1096',
    'de3bbc64-edad-4ff4-bccd-c2ef217c1d56','2847c0be-3e31-45a5-957c-508729f1971e');
  if p_intake_enabled or p_print_enabled then
    if v_state->>'mode' is distinct from 'blocked' or not exists(
      select 1 from public.restaurant_storefront_profiles s join public.branches b
        on (b.organization_id,b.restaurant_id,b.id)=(s.organization_id,s.restaurant_id,s.storefront_branch_id)
      where s.slug='mapsburger' and s.organization_id='20605c2b-3145-4803-a990-bbec3d9c1096'
        and s.restaurant_id='de3bbc64-edad-4ff4-bccd-c2ef217c1d56'
        and s.storefront_branch_id='2847c0be-3e31-45a5-957c-508729f1971e'
        and s.deleted_at is null and s.is_published and s.pickup_enabled and not s.delivery_enabled
        and b.kitchen_workflow_mode='printer_only' and b.status='active' and b.deleted_at is null)
      or exists(select 1 from unnest(v_devices) id where not exists(
        select 1 from public.devices d where d.id=id and d.organization_id='20605c2b-3145-4803-a990-bbec3d9c1096'
          and d.restaurant_id='de3bbc64-edad-4ff4-bccd-c2ef217c1d56'
          and d.branch_id='2847c0be-3e31-45a5-957c-508729f1971e' and d.device_type='pos'
          and d.deleted_at is null)) then
      raise exception 'rollout protection/scope unavailable' using errcode='23514';
    end if;
  end if;
  v_revision:=nextval('app.kitchen_print_containment_revision');
  if v_previous.print_enabled and p_print_enabled and v_previous.allowed_device_ids=v_devices
    and v_previous.containment_revision=(v_state->>'revision')::bigint then
    v_generation:=v_previous.print_generation; v_cutoff:=v_previous.admission_cutoff;
  else
    v_generation:=v_revision; v_cutoff:=clock_timestamp();
  end if;
  insert into app.mapsburger_web_order_rollouts(revision,intake_enabled,print_enabled,print_generation,
    allowed_device_ids,containment_revision,admission_cutoff,reason,operator_reference)
  values(v_revision,p_intake_enabled,p_print_enabled,v_generation,v_devices,
    (v_state->>'revision')::bigint,v_cutoff,p_reason,p_operator_reference);
  if not p_intake_enabled then
    update public.web_order_channel_settings set submission_enabled=false,updated_at=clock_timestamp()
      where organization_id='20605c2b-3145-4803-a990-bbec3d9c1096'
        and restaurant_id='de3bbc64-edad-4ff4-bccd-c2ef217c1d56'
        and branch_id='2847c0be-3e31-45a5-957c-508729f1971e';
  end if;
  return v_revision;
end; $$;
revoke all on function app.set_mapsburger_web_orders(boolean,boolean,uuid[],text,text)
  from public,anon,authenticated,service_role;

create function app.mapsburger_live_ordering_open(p_slug text) returns boolean
language sql stable security definer set search_path='' as $$
  select p_slug='mapsburger' and exists (
    select 1 from (select * from app.mapsburger_web_order_rollouts order by revision desc limit 1) r
    join public.restaurant_storefront_profiles s using(organization_id,restaurant_id)
    join public.web_order_channel_settings c using(organization_id,restaurant_id,branch_id)
    where s.slug=p_slug and s.storefront_branch_id=r.branch_id and s.deleted_at is null
      and s.is_published and s.pickup_enabled and not s.delivery_enabled
      and r.intake_enabled and r.print_enabled and c.submission_enabled
      and app.kitchen_print_containment_state(r.organization_id,r.restaurant_id,r.branch_id)->>'mode'='blocked'
      and (app.kitchen_print_containment_state(r.organization_id,r.restaurant_id,r.branch_id)->>'revision')::bigint=r.containment_revision
  );
$$;
revoke all on function app.mapsburger_live_ordering_open(text) from public,anon,authenticated,service_role;

create or replace function public.storefront_menu(p_slug text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v jsonb;
begin
  v:=app.storefront_menu_browse_only_manual_pilot_001(p_slug);
  if v->>'ok'='true' then
    v:=jsonb_set(v,'{service,ordering_enabled}',to_jsonb(
      v->'service'->>'state'='open' and (v->'service'->>'pickup_enabled')::boolean
      and (app.mapsburger_live_ordering_open(p_slug) or app.storefront_manual_order_pilot_open(p_slug))));
  end if;
  return v;
end; $$;
revoke all on function public.storefront_menu(text) from public,anon,authenticated,service_role;
grant execute on function public.storefront_menu(text) to anon,service_role;

create function app.submit_web_order_live_request(
  p_slug text,p_client_request_id uuid,p_status_token_hash text,p_order jsonb
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_rollout app.mapsburger_web_order_rollouts; v_result jsonb; v_request public.web_order_requests;
begin
  if p_slug is distinct from 'mapsburger' then
    return jsonb_build_object('ok',false,'error','ordering_unavailable');
  end if;
  -- Identity before branch matches the unchanged delegated writer. OFF holds
  -- the exclusive branch lock until committed, so no post-OFF fresh admission.
  perform pg_advisory_xact_lock(hashtextextended('de3bbc64-edad-4ff4-bccd-c2ef217c1d56:'||p_client_request_id::text,0));
  perform app.lock_kitchen_print_containment('2847c0be-3e31-45a5-957c-508729f1971e',false);
  select * into v_request from public.web_order_requests
    where restaurant_id='de3bbc64-edad-4ff4-bccd-c2ef217c1d56' and client_request_id=p_client_request_id;
  if found then
    -- Exact payload/capability idempotency and quota contract survives OFF.
    return app.submit_web_order_request(p_slug,p_client_request_id,p_status_token_hash,p_order);
  end if;
  select * into v_rollout from app.mapsburger_web_order_rollouts order by revision desc limit 1;
  if not found or not app.mapsburger_live_ordering_open(p_slug) then
    return jsonb_build_object('ok',false,'error','ordering_unavailable');
  end if;
  v_result:=app.submit_web_order_request(p_slug,p_client_request_id,p_status_token_hash,p_order);
  if v_result->>'ok' is distinct from 'true' then return v_result; end if;
  select * into v_request from public.web_order_requests where restaurant_id=v_rollout.restaurant_id
    and client_request_id=p_client_request_id and branch_id=v_rollout.branch_id;
  if not found or v_result->>'replayed' is distinct from 'false'
    or v_request.created_at<v_rollout.admission_cutoff then
    raise exception 'live request enrollment mismatch' using errcode='23514';
  end if;
  insert into app.mapsburger_live_web_requests(request_id,rollout_revision,print_generation)
    values(v_request.id,v_rollout.revision,v_rollout.print_generation);
  return v_result;
end; $$;
create function public.submit_web_order_live_request(
  p_slug text,p_client_request_id uuid,p_status_token_hash text,p_order jsonb
) returns jsonb language sql volatile security invoker set search_path='' as $$
  select app.submit_web_order_live_request(p_slug,p_client_request_id,p_status_token_hash,p_order);
$$;
revoke all on function app.submit_web_order_live_request(text,uuid,text,jsonb),
  public.submit_web_order_live_request(text,uuid,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function app.submit_web_order_live_request(text,uuid,text,jsonb),
  public.submit_web_order_live_request(text,uuid,text,jsonb) to service_role;

-- The projection is v63's EXISTING exact-target wire contract, not ordinary
-- mode and not a new unrecognized mode. It cannot authorize a broad pull or a
-- local ordinary queued job. Config/lease/closure revisions share one sequence.
create function app.mapsburger_device_print_policy(
  p_org uuid,p_rest uuid,p_branch uuid,p_device uuid,p_session_token text
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_base jsonb; v_rollout app.mapsburger_web_order_rollouts; v_lease app.mapsburger_web_print_leases;
  v_revision bigint; v_closed bigint;
begin
  v_base:=app.kitchen_print_containment_state(p_org,p_rest,p_branch);
  if p_branch<>'2847c0be-3e31-45a5-957c-508729f1971e'::uuid then return v_base; end if;
  select * into v_rollout from app.mapsburger_web_order_rollouts order by revision desc limit 1;
  if not found then return v_base; end if;
  select * into v_lease from app.mapsburger_web_print_leases where device_id=p_device order by revision desc limit 1;
  select coalesce(max(c.revision),0) into v_closed from app.mapsburger_web_print_lease_closures c
    join app.mapsburger_web_print_leases l using(request_id) where l.device_id=p_device;
  v_revision:=greatest((v_base->>'revision')::bigint,v_rollout.revision,coalesce(v_lease.revision,0),v_closed);
  v_base:=v_base||jsonb_build_object('mode','blocked','revision',v_revision,'target_request_id',null,'expires_at',null);
  if v_rollout.print_enabled and p_device=any(v_rollout.allowed_device_ids)
    and v_rollout.containment_revision=(app.kitchen_print_containment_state(p_org,p_rest,p_branch)->>'revision')::bigint
    and app.kitchen_print_containment_state(p_org,p_rest,p_branch)->>'mode'='blocked'
    and v_lease.print_generation=v_rollout.print_generation and v_lease.expires_at>clock_timestamp()
    and v_lease.session_fingerprint=encode(sha256(convert_to(p_session_token,'UTF8')),'hex')
    and not exists(select 1 from app.mapsburger_web_print_lease_closures c where c.request_id=v_lease.request_id)
    and exists(select 1 from public.web_order_print_attempts a
      join public.web_order_decisions d on d.request_id=a.request_id
      join public.web_order_requests w on w.id=a.request_id
      where a.request_id=v_lease.request_id and a.organization_id=p_org and a.restaurant_id=p_rest and a.branch_id=p_branch
        and a.canonical_order_id=v_lease.canonical_order_id and a.decision_id=v_lease.decision_id
        and a.dispatch_id=v_lease.dispatch_id and a.finished_at is null
        and w.status='accepted' and w.canonical_order_id=a.canonical_order_id
        and d.decision='accepted' and d.device_id=p_device and d.pin_session_id=v_lease.pin_session_id
        and d.decision_id=a.decision_id and d.canonical_order_id=a.canonical_order_id)
    and not exists(select 1 from public.kitchen_print_dispatch_holds h where h.dispatch_id=v_lease.dispatch_id) then
    return v_base||jsonb_build_object('mode','target_only','target_request_id',v_lease.request_id,'expires_at',v_lease.expires_at);
  end if;
  return v_base;
end; $$;
revoke all on function app.mapsburger_device_print_policy(uuid,uuid,uuid,uuid,text) from public,anon,authenticated,service_role;

create or replace function app.pos_accept_web_order(
  p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,p_request_id uuid,p_decision_id uuid
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_branch uuid; v_context jsonb; v_rollout app.mapsburger_web_order_rollouts; v_result jsonb;
  v_request public.web_order_requests; v_target public.web_order_print_attempts;
begin
  select ds.branch_id into v_branch from public.device_sessions ds where ds.device_id=p_device_id
    and ds.session_token_ref=app.hash_provisioning_secret(btrim(p_device_session_token))
    and ds.is_active and ds.revoked_at is null and (ds.expires_at is null or ds.expires_at>clock_timestamp());
  if v_branch is distinct from '2847c0be-3e31-45a5-957c-508729f1971e'::uuid
    or not exists(select 1 from app.mapsburger_web_order_rollouts) then
    return app.decide_pos_web_order(p_pin_session_id,p_device_id,p_device_session_token,p_request_id,p_decision_id,'accepted',null);
  end if;
  perform app.lock_kitchen_print_containment(v_branch,false);
  -- This lock precedes context/hierarchy/request/sync locks everywhere in this
  -- new path. A second accepted callback cannot displace an in-flight lease.
  perform pg_advisory_xact_lock(hashtextextended('mapsburger-web-print-device:'||p_device_id::text,0));
  v_context:=app.pos_web_order_context(p_pin_session_id,p_device_id,p_device_session_token);
  if v_context->>'ok' is distinct from 'true' then return v_context; end if;
  select * into v_request from public.web_order_requests where id=p_request_id
    and organization_id=(v_context->>'organization_id')::uuid and restaurant_id=(v_context->>'restaurant_id')::uuid
    and branch_id=v_branch;
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
  if v_request.status='accepted' then
    -- Old/replayed acceptance NEVER allocates or reselects a target lease.
    return app.decide_pos_web_order(p_pin_session_id,p_device_id,p_device_session_token,p_request_id,p_decision_id,'accepted',null);
  end if;
  select * into v_rollout from app.mapsburger_web_order_rollouts order by revision desc limit 1;
  if not v_rollout.print_enabled or not p_device_id=any(v_rollout.allowed_device_ids)
    or app.kitchen_print_containment_state(v_rollout.organization_id,v_rollout.restaurant_id,v_branch)->>'mode'<>'blocked'
    or (app.kitchen_print_containment_state(v_rollout.organization_id,v_rollout.restaurant_id,v_branch)->>'revision')::bigint<>v_rollout.containment_revision
    or not exists(select 1 from app.mapsburger_live_web_requests e
      where e.request_id=p_request_id and e.print_generation=v_rollout.print_generation)
    then return jsonb_build_object('ok',false,'error','ordering_unavailable'); end if;
  -- Permanent tombstones; expiry does not reselect a stale request. A reserved
  -- but unfinished attempt requires reconciliation, even after lease expiry.
  insert into app.mapsburger_web_print_lease_closures(request_id,reason)
  select l.request_id,case when a.finished_at is not null then 'terminal_attempt' else 'expired_before_send' end
    from app.mapsburger_web_print_leases l join public.web_order_print_attempts a using(request_id)
    where l.device_id=p_device_id and (a.finished_at is not null or (l.expires_at<=clock_timestamp() and a.attempt_id is null))
      and not exists(select 1 from app.mapsburger_web_print_lease_closures c where c.request_id=l.request_id);
  if exists(select 1 from app.mapsburger_web_print_leases l
    where l.device_id=p_device_id and not exists(select 1 from app.mapsburger_web_print_lease_closures c where c.request_id=l.request_id)) then
    -- v63 understands this typed, retryable rejection and clears its intent.
    -- An unknown new "busy" error would instead create an uncertain decision.
    return jsonb_build_object('ok',false,'error','order_rejected');
  end if;
  v_result:=app.decide_pos_web_order(p_pin_session_id,p_device_id,p_device_session_token,p_request_id,p_decision_id,'accepted',null);
  if v_result->>'ok' is distinct from 'true' or v_result->>'replayed' is distinct from 'false' then return v_result; end if;
  select * into v_target from public.web_order_print_attempts where request_id=p_request_id;
  if not found or v_target.canonical_order_id::text is distinct from v_result->>'canonical_order_id'
    or v_target.decision_id::text is distinct from v_result->>'decision_id' then
    raise exception 'accepted live print enrollment missing' using errcode='23514';
  end if;
  insert into app.mapsburger_web_print_leases(request_id,device_id,session_fingerprint,pin_session_id,
    canonical_order_id,decision_id,dispatch_id,print_generation,expires_at)
  values(p_request_id,p_device_id,encode(sha256(convert_to(p_device_session_token,'UTF8')),'hex'),p_pin_session_id,
    v_target.canonical_order_id,v_target.decision_id,v_target.dispatch_id,v_rollout.print_generation,
    clock_timestamp()+interval '5 minutes');
  return v_result;
end; $$;
revoke all on function app.pos_accept_web_order(uuid,uuid,text,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function app.pos_accept_web_order(uuid,uuid,text,uuid,uuid) to authenticated;

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
    ||app.mapsburger_device_print_policy((v_proof->>'organization_id')::uuid,(v_proof->>'restaurant_id')::uuid,v_branch,p_device_id,p_session_token);
end; $$;
revoke all on function app.pos_kitchen_print_containment(uuid,text) from public,anon,authenticated,service_role;
grant execute on function app.pos_kitchen_print_containment(uuid,text) to authenticated;

-- TARGET_OPERATION_BODY follows. Its claim/readiness/reservation/finish code is
-- copied byte-for-byte except the two existing admission predicate reads.
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
  v_policy:=app.mapsburger_device_print_policy(v_target.organization_id,v_target.restaurant_id,v_target.branch_id,p_device_id,p_device_session_token);
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
  v_policy:=app.mapsburger_device_print_policy(v_target.organization_id,v_target.restaurant_id,v_target.branch_id,p_device_id,p_device_session_token);
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
revoke all on function app.pos_web_order_print_operation(uuid,uuid,text,uuid,text,uuid,text,text)
  from public,anon,authenticated,service_role;



commit;
