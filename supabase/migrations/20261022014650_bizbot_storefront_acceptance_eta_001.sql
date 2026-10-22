-- BIZBOT-STOREFRONT-ACCEPTANCE-ETA-001: additive, explicit future acceptance ETA.
-- Legacy writers and public response shapes are deliberately unchanged.
begin;

create function app.web_order_acceptance_intent_fingerprint(
  p_organization_id uuid,p_restaurant_id uuid,p_branch_id uuid,
  p_request_id uuid,p_decision_id uuid,p_preparation_minutes integer
) returns text language sql immutable strict set search_path='' as $$
  select encode(sha256(convert_to(jsonb_build_object('version',1,'action','accepted',
    'organization_id',p_organization_id,'restaurant_id',p_restaurant_id,'branch_id',p_branch_id,
    'request_id',p_request_id,'decision_id',p_decision_id,'preparation_minutes',p_preparation_minutes)::text,'UTF8')),'hex');
$$;
revoke all on function app.web_order_acceptance_intent_fingerprint(uuid,uuid,uuid,uuid,uuid,integer)
  from public,anon,authenticated,service_role;

create table app.web_order_acceptance_estimates (
  request_id uuid primary key references public.web_order_decisions(request_id) on delete restrict,
  organization_id uuid not null,
  restaurant_id uuid not null,
  branch_id uuid not null,
  decision_id uuid not null,
  intent_fingerprint text not null check (length(intent_fingerprint)=64 and intent_fingerprint ~ '^[0-9a-f]{64}$'),
  preparation_minutes integer not null check (preparation_minutes between 1 and 240),
  accepted_at timestamptz not null,
  ready_at timestamptz not null,
  timezone text not null check (length(timezone) between 1 and 100
    and (timezone='UTC' or timezone ~ '^[A-Za-z_]+(/[A-Za-z0-9_+\-]+)+$')
    and timezone !~ '^(posix|right)/'),
  check (ready_at=accepted_at+preparation_minutes*interval '1 minute'),
  foreign key(organization_id,restaurant_id,branch_id,request_id)
    references public.web_order_requests(organization_id,restaurant_id,branch_id,id) on delete restrict,
  foreign key(organization_id,restaurant_id,branch_id,decision_id)
    references public.web_order_decisions(organization_id,restaurant_id,branch_id,decision_id) on delete restrict
);
alter table app.web_order_acceptance_estimates enable row level security;
alter table app.web_order_acceptance_estimates force row level security;
revoke all on app.web_order_acceptance_estimates from public,anon,authenticated,service_role;
create trigger web_order_acceptance_estimates_append_only
  before update or delete on app.web_order_acceptance_estimates
  for each row execute function app.enforce_audit_append_only();
create trigger web_order_acceptance_estimates_no_truncate
  before truncate on app.web_order_acceptance_estimates
  for each statement execute function app.enforce_audit_append_only();

create function app.check_web_order_acceptance_estimate() returns trigger
language plpgsql set search_path='' as $$
begin
  -- Even a privileged SQL insert cannot attach an estimate to another winner
  -- or timestamp. The immutable decision, not this function's clock, owns time.
  if not exists(select 1 from public.web_order_requests w join public.web_order_decisions d
      on d.request_id=w.id and d.organization_id=w.organization_id
        and d.restaurant_id=w.restaurant_id and d.branch_id=w.branch_id
      where w.id=new.request_id and w.organization_id=new.organization_id
        and w.restaurant_id=new.restaurant_id and w.branch_id=new.branch_id
        and w.status='accepted' and d.decision='accepted'
        and d.decision_id=new.decision_id and d.decided_at=new.accepted_at
        and w.decided_at=new.accepted_at and d.canonical_order_id=w.canonical_order_id)
    or new.intent_fingerprint<>app.web_order_acceptance_intent_fingerprint(new.organization_id,new.restaurant_id,
      new.branch_id,new.request_id,new.decision_id,new.preparation_minutes)
    or not exists(select 1 from pg_catalog.pg_timezone_names z where z.name=new.timezone) then
    raise exception 'ACCEPTANCE_ETA_MAPPING_UNAVAILABLE' using errcode='23514';
  end if;
  return new;
end; $$;
revoke all on function app.check_web_order_acceptance_estimate() from public,anon,authenticated,service_role;
create trigger web_order_acceptance_estimates_insert_guard
  before insert on app.web_order_acceptance_estimates
  for each row execute function app.check_web_order_acceptance_estimate();
comment on table app.web_order_acceptance_estimates is
  'Explicit future ETA only; private forced-RLS append-only winning-decision sidecar. No historical backfill, customer/contact capability, print mutation or independent accept authority.';

create function app.pos_accept_web_order_with_eta(
  p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,
  p_request_id uuid,p_decision_id uuid,p_preparation_minutes integer
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare
  v_result jsonb; v_request public.web_order_requests; v_decision public.web_order_decisions;
  v_estimate app.web_order_acceptance_estimates; v_timezone text; v_context jsonb; v_branch uuid;
  v_fingerprint text; v_platform boolean; v_legacy_print boolean;
begin
  if p_preparation_minutes is null or p_preparation_minutes not between 1 and 240 then
    return jsonb_build_object('ok',false,'error','invalid_request','entity','web_order_request');
  end if;
  -- One subtransaction includes ALL existing canonical/audit/decision/lease
  -- effects plus metadata. A metadata fault is raised, never caught as success.
  begin
    -- Match the existing resolver's lock order, without copying its fixed
    -- historical tenant IDs: platform enrollment first; otherwise the legacy
    -- rollout's constrained scope. Ordinary legacy requests use context first.
    select ds.branch_id into v_branch from public.device_sessions ds where ds.device_id=p_device_id
      and ds.session_token_ref=app.hash_provisioning_secret(btrim(p_device_session_token))
      and ds.is_active and ds.revoked_at is null and (ds.expires_at is null or ds.expires_at>clock_timestamp());
    if v_branch is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
    v_platform:=exists(select 1 from app.online_order_live_requests where request_id=p_request_id);
    v_legacy_print:=not v_platform and exists(select 1 from app.mapsburger_web_order_rollouts where branch_id=v_branch);
    if v_platform or v_legacy_print then
      perform app.lock_kitchen_print_containment(v_branch,false);
      perform pg_advisory_xact_lock(hashtextextended(
        (case when v_platform then 'online-order-print-device:' else 'mapsburger-web-print-device:' end)||p_device_id::text,0));
    end if;
    v_context:=app.pos_web_order_context(p_pin_session_id,p_device_id,p_device_session_token);
    if v_context->>'ok' is distinct from 'true' then return v_context; end if;
    select * into v_request from public.web_order_requests where id=p_request_id
      and organization_id=(v_context->>'organization_id')::uuid
      and restaurant_id=(v_context->>'restaurant_id')::uuid and branch_id=v_branch for update;
    if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
    if v_request.status='pending' then
      -- Context already holds hierarchy SHARE locks. Validate the effective
      -- zone before old acceptance can write any canonical/order/lease state.
      select coalesce(b.timezone,r.timezone) into v_timezone
        from public.branches b join public.restaurants r on r.id=b.restaurant_id
          and r.organization_id=b.organization_id
        where b.id=v_request.branch_id and b.restaurant_id=v_request.restaurant_id
          and b.organization_id=v_request.organization_id;
      if v_timezone is null or length(v_timezone) not between 1 and 100
        or not (v_timezone='UTC' or v_timezone ~ '^[A-Za-z_]+(/[A-Za-z0-9_+\-]+)+$')
        or v_timezone ~ '^(posix|right)/'
        or not exists(select 1 from pg_catalog.pg_timezone_names z where z.name=v_timezone) then
        return jsonb_build_object('ok',false,'error','ordering_unavailable','entity','web_order_request');
      end if;
    end if;
    v_result:=app.pos_accept_web_order(p_pin_session_id,p_device_id,p_device_session_token,
      p_request_id,p_decision_id);
    if v_result->>'ok' is distinct from 'true' then return v_result; end if;
    select * into v_request from public.web_order_requests where id=p_request_id;
    select * into v_decision from public.web_order_decisions where request_id=p_request_id
      and organization_id=v_request.organization_id and restaurant_id=v_request.restaurant_id
      and branch_id=v_request.branch_id and decision_id=p_decision_id
      and device_id=p_device_id and pin_session_id=p_pin_session_id
      and decision='accepted' and canonical_order_id=v_request.canonical_order_id
      and decided_at=v_request.decided_at;
    if not found or v_request.status is distinct from 'accepted'
      or v_result->>'status' is distinct from 'accepted'
      or v_result->>'decision_id' is distinct from p_decision_id::text then
      -- A legacy replay from a different winning identity must not gain ETA.
      if v_result->>'replayed'='true' then
        return jsonb_build_object('ok',false,'error','decision_conflict','entity','web_order_request');
      end if;
      raise exception 'ACCEPTANCE_ETA_MAPPING_UNAVAILABLE' using errcode='23514';
    end if;
    v_fingerprint:=app.web_order_acceptance_intent_fingerprint(v_request.organization_id,v_request.restaurant_id,
      v_request.branch_id,p_request_id,p_decision_id,p_preparation_minutes);
    select * into v_estimate from app.web_order_acceptance_estimates where request_id=p_request_id;
    if v_result->>'replayed'='true' then
      -- Do not read the current timezone or backfill an old acceptance.
      if not found or v_estimate.organization_id<>v_request.organization_id
        or v_estimate.restaurant_id<>v_request.restaurant_id or v_estimate.branch_id<>v_request.branch_id
        or v_estimate.decision_id<>p_decision_id or v_estimate.accepted_at<>v_decision.decided_at
        or v_estimate.preparation_minutes<>p_preparation_minutes or v_estimate.intent_fingerprint<>v_fingerprint then
        return jsonb_build_object('ok',false,'error','decision_conflict','entity','web_order_request');
      end if;
      return v_result;
    end if;
    if v_result->>'replayed' is distinct from 'false' or found then
      raise exception 'ACCEPTANCE_ETA_MAPPING_UNAVAILABLE' using errcode='23514';
    end if;
    insert into app.web_order_acceptance_estimates(request_id,organization_id,restaurant_id,branch_id,
      decision_id,intent_fingerprint,preparation_minutes,accepted_at,ready_at,timezone)
    values(v_request.id,v_request.organization_id,v_request.restaurant_id,v_request.branch_id,
      v_decision.decision_id,v_fingerprint,p_preparation_minutes,v_decision.decided_at,
      v_decision.decided_at+p_preparation_minutes*interval '1 minute',v_timezone);
    return v_result;
  exception when others then
    raise;
  end;
end; $$;
create function public.pos_accept_web_order_with_eta(
  p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,
  p_request_id uuid,p_decision_id uuid,p_preparation_minutes integer
) returns jsonb language sql volatile security invoker set search_path='' as $$
  select app.pos_accept_web_order_with_eta(p_pin_session_id,p_device_id,p_device_session_token,
    p_request_id,p_decision_id,p_preparation_minutes);
$$;
revoke all on function app.pos_accept_web_order_with_eta(uuid,uuid,text,uuid,uuid,integer),
  public.pos_accept_web_order_with_eta(uuid,uuid,text,uuid,uuid,integer) from public,anon,authenticated,service_role;
grant execute on function app.pos_accept_web_order_with_eta(uuid,uuid,text,uuid,uuid,integer),
  public.pos_accept_web_order_with_eta(uuid,uuid,text,uuid,uuid,integer) to authenticated;
alter function app.pos_accept_web_order_with_eta(uuid,uuid,text,uuid,uuid,integer) owner to postgres;

create function app.web_order_public_result_v2(p_request public.web_order_requests,p_replayed boolean)
returns jsonb language plpgsql volatile set search_path='' as $$
declare v_result jsonb; v_estimate app.web_order_acceptance_estimates;
begin
  v_result:=app.web_order_public_result(p_request,p_replayed);
  if p_request.status<>'accepted' then return v_result; end if;
  select * into v_estimate from app.web_order_acceptance_estimates where request_id=p_request.id;
  if not found then return v_result; end if;
  if v_estimate.organization_id<>p_request.organization_id or v_estimate.restaurant_id<>p_request.restaurant_id
    or v_estimate.branch_id<>p_request.branch_id or v_estimate.accepted_at<>p_request.decided_at
    or v_estimate.intent_fingerprint<>app.web_order_acceptance_intent_fingerprint(p_request.organization_id,
      p_request.restaurant_id,p_request.branch_id,p_request.id,v_estimate.decision_id,v_estimate.preparation_minutes)
    or not exists(select 1 from public.web_order_decisions d where d.request_id=p_request.id
      and d.organization_id=p_request.organization_id and d.restaurant_id=p_request.restaurant_id
      and d.branch_id=p_request.branch_id and d.decision='accepted'
      and d.decision_id=v_estimate.decision_id and d.decided_at=v_estimate.accepted_at
      and d.canonical_order_id=p_request.canonical_order_id) then
    raise exception 'ACCEPTANCE_ETA_MAPPING_UNAVAILABLE' using errcode='23514';
  end if;
  return v_result||jsonb_build_object('acceptance_eta',jsonb_build_object(
    'preparation_minutes',v_estimate.preparation_minutes,
    'accepted_at',to_char(v_estimate.accepted_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'ready_at',to_char(v_estimate.ready_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),
    'timezone',v_estimate.timezone));
end; $$;
revoke all on function app.web_order_public_result_v2(public.web_order_requests,boolean)
  from public,anon,authenticated,service_role;

-- Capability admission, channel lock, post-wait reread and quota are identical
-- to v1; no nested status call and no unchecked second request lookup.
create function app.get_web_order_request_status_v2(p_slug text,p_client_request_id uuid,p_status_token_hash text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_profile public.restaurant_storefront_profiles; v_request public.web_order_requests;
  v_channel public.web_order_channel_settings; v_branch uuid; v_found boolean; v_now timestamptz;
begin
  if p_slug is null or length(p_slug) not between 3 and 48
    or p_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or p_client_request_id is null
    or p_status_token_hash is null or p_status_token_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok',false,'error','not_found');
  end if;
  select * into v_profile from public.restaurant_storefront_profiles where slug=p_slug and deleted_at is null;
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
  select * into v_request from public.web_order_requests
    where restaurant_id=v_profile.restaurant_id and client_request_id=p_client_request_id
      and status_token_hash=p_status_token_hash and status_until>v_now;
  v_found:=found;
  if v_channel.status_attempt_count>=600 then
    return jsonb_build_object('ok',false,'error',case when v_found then 'rate_limited' else 'not_found' end);
  end if;
  update public.web_order_channel_settings set status_window_started_at=v_channel.status_window_started_at,
    status_attempt_count=v_channel.status_attempt_count+1,updated_at=v_now where branch_id=v_branch;
  if not v_found then return jsonb_build_object('ok',false,'error','not_found'); end if;
  return app.web_order_public_result_v2(v_request,false);
end; $$;
create function public.get_web_order_request_status_v2(p_slug text,p_client_request_id uuid,p_status_token_hash text)
returns jsonb language sql security invoker set search_path='' as $$
  select app.get_web_order_request_status_v2(p_slug,p_client_request_id,p_status_token_hash);
$$;
revoke all on function app.get_web_order_request_status_v2(text,uuid,text),
  public.get_web_order_request_status_v2(text,uuid,text) from public,anon,authenticated,service_role;
grant execute on function app.get_web_order_request_status_v2(text,uuid,text),
  public.get_web_order_request_status_v2(text,uuid,text) to service_role;
alter function app.get_web_order_request_status_v2(text,uuid,text) owner to postgres;

commit;
