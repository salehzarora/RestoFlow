-- BIZBOT-POS-BACKGROUND-ORDER-ALERT-001. Notification-only, default OFF.
-- Existing append-only receipt/decision records are the transactional outbox.
-- No order, pricing, printing, admission, scheduler or historic row is changed.
create table app.pos_order_alert_settings (
  revision bigint generated always as identity primary key,
  enabled boolean not null,
  created_at timestamptz not null default clock_timestamp(),
  reason text not null check(length(btrim(reason)) between 1 and 300),
  operator_reference text not null check(length(btrim(operator_reference)) between 1 and 200)
);
create table app.pos_order_alert_registrations (
  id uuid primary key default gen_random_uuid(),
  installation_id uuid not null unique,
  generation uuid not null default gen_random_uuid(),
  setting_revision bigint not null references app.pos_order_alert_settings(revision),
  organization_id uuid not null,
  restaurant_id uuid not null,
  branch_id uuid not null,
  device_id uuid not null references public.devices(id),
  device_session_id uuid not null references public.device_sessions(id),
  pin_session_id uuid not null references public.pin_sessions(id),
  employee_profile_id uuid not null references public.employee_profiles(id),
  resolved_membership_id uuid not null references public.memberships(id),
  fcm_token text not null check(length(fcm_token) between 20 and 4096 and fcm_token !~ '[[:space:][:cntrl:]]'),
  token_hash text not null check(token_hash ~ '^[0-9a-f]{64}$'),
  status_secret_hash text not null check(status_secret_hash ~ '^[0-9a-f]{64}$'),
  enabled boolean not null default true,
  registered_at timestamptz not null default clock_timestamp(),
  refreshed_at timestamptz not null default clock_timestamp(),
  authority_expires_at timestamptz not null,
  check(organization_id='20605c2b-3145-4803-a990-bbec3d9c1096'::uuid
    and restaurant_id='de3bbc64-edad-4ff4-bccd-c2ef217c1d56'::uuid
    and branch_id='2847c0be-3e31-45a5-957c-508729f1971e'::uuid
    and device_id='bb80c0d8-6893-4e24-8eea-5a14cf545ecd'::uuid),
  check(registered_at<=refreshed_at and authority_expires_at>refreshed_at
    and authority_expires_at<=refreshed_at+interval '8 hours')
);
create unique index pos_order_alert_one_token on app.pos_order_alert_registrations(token_hash) where enabled;
create unique index pos_order_alert_one_device on app.pos_order_alert_registrations(device_id) where enabled;
create table app.pos_order_alert_deliveries (
  id uuid primary key default gen_random_uuid(),
  registration_id uuid not null references app.pos_order_alert_registrations(id),
  generation uuid not null,
  request_id uuid not null references public.web_order_requests(id),
  kind text not null check(kind in ('pending','terminal')),
  state text not null default 'queued' check(state in ('queued','leased','sent','abandoned')),
  attempt_count integer not null default 0 check(attempt_count between 0 and 3),
  next_attempt_at timestamptz not null default statement_timestamp(),
  lease_id uuid,
  lease_until timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  sent_at timestamptz,
  unique(registration_id,generation,request_id,kind)
);
create index pos_order_alert_delivery_queue on app.pos_order_alert_deliveries(next_attempt_at) where state in ('queued','leased');

-- Private RPC-only tables: no Data API role has direct table access.
do $$ declare t text; begin
  foreach t in array array['pos_order_alert_settings','pos_order_alert_registrations','pos_order_alert_deliveries'] loop
    execute format('alter table app.%I enable row level security',t);
    execute format('alter table app.%I force row level security',t);
    execute format('create policy deny_client on app.%I for all to authenticated using(false) with check(false)',t);
    execute format('revoke all on app.%I from public,anon,authenticated,service_role',t);
  end loop;
end; $$;
revoke all on sequence app.pos_order_alert_settings_revision_seq from public,anon,authenticated,service_role;

-- Operator only. No feature row is installed; absence is OFF. Re-enabling uses
-- a new cutoff and requires foreground registration, never old-request backfill.
create function app.set_pos_order_alerts(p_enabled boolean,p_reason text,p_operator_reference text)
returns bigint language plpgsql security definer set search_path='' as $$
declare v_revision bigint;
begin
  if p_enabled is null then raise exception 'enabled required' using errcode='22023'; end if;
  insert into app.pos_order_alert_settings(enabled,reason,operator_reference)
    values(p_enabled,p_reason,p_operator_reference) returning revision into v_revision;
  return v_revision;
end; $$;
revoke all on function app.set_pos_order_alerts(boolean,text,text) from public,anon,authenticated,service_role;
create trigger pos_order_alert_settings_append_only before update or delete on app.pos_order_alert_settings
  for each row execute function app.enforce_audit_append_only();
create trigger pos_order_alert_settings_no_truncate before truncate on app.pos_order_alert_settings
  for each statement execute function app.enforce_audit_append_only();

-- TRUE READ ONLY: no renewal, heartbeat, session restoration, quota, audit or
-- claim. Re-prove current authority on every status read AND worker claim.
create function app.pos_order_alert_authority(p_registration app.pos_order_alert_registrations)
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
   and b.status='active' and b.deleted_at is null;
$$;
revoke all on function app.pos_order_alert_authority(app.pos_order_alert_registrations) from public,anon,authenticated,service_role;

create function app.pos_register_order_alert(p_installation_id uuid,p_fcm_token text,p_status_secret text,
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
  if p_device_id<>'bb80c0d8-6893-4e24-8eea-5a14cf545ecd'::uuid
    or v_context->>'organization_id'<>'20605c2b-3145-4803-a990-bbec3d9c1096'
    or v_context->>'restaurant_id'<>'de3bbc64-edad-4ff4-bccd-c2ef217c1d56'
    or v_context->>'branch_id'<>'2847c0be-3e31-45a5-957c-508729f1971e' then
    return jsonb_build_object('ok',false,'error','permission_denied'); end if;
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
  on conflict(installation_id) do update set generation=case when app.pos_order_alert_registrations.fcm_token=excluded.fcm_token
      and app.pos_order_alert_registrations.status_secret_hash=excluded.status_secret_hash
      and app.pos_order_alert_registrations.pin_session_id=excluded.pin_session_id
      and app.pos_order_alert_registrations.device_session_id=excluded.device_session_id
      and app.pos_order_alert_registrations.setting_revision=excluded.setting_revision
      then app.pos_order_alert_registrations.generation else gen_random_uuid() end,
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
  return jsonb_build_object('ok',true,'registration_id',v_registration.id,'authority_expires_at',v_deadline);
end; $$;
create function public.pos_register_order_alert(p_installation_id uuid,p_fcm_token text,p_status_secret text,
  p_device_id uuid,p_pin_session_id uuid,p_device_session_token text)
returns jsonb language sql volatile security invoker set search_path='' as $$
 select app.pos_register_order_alert(p_installation_id,p_fcm_token,p_status_secret,p_device_id,p_pin_session_id,p_device_session_token);
$$;
revoke all on function app.pos_register_order_alert(uuid,text,text,uuid,uuid,text),
 public.pos_register_order_alert(uuid,text,text,uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function app.pos_register_order_alert(uuid,text,text,uuid,uuid,text),
 public.pos_register_order_alert(uuid,text,text,uuid,uuid,text) to authenticated;

create function app.pos_order_alert_status(p_installation_id uuid,p_status_secret_hash text)
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
      join app.mapsburger_live_web_requests live on live.request_id=w.id
      join app.pos_order_alert_settings s on s.revision=v_registration.setting_revision
      where w.organization_id=v_registration.organization_id and w.restaurant_id=v_registration.restaurant_id
        and w.branch_id=v_registration.branch_id and w.status='pending' and w.expires_at>v_now
        and w.created_at>=s.created_at order by w.created_at,w.id limit 51) q;
  if jsonb_array_length(v_rows)>50 then return jsonb_build_object('ok',false,'error','capacity_exceeded'); end if;
  return jsonb_build_object('ok',true,'server_time',v_now,'registration_id',v_registration.id,'authority_expires_at',v_deadline,'requests',v_rows);
end; $$;
create function public.pos_order_alert_status(p_installation_id uuid,p_status_secret_hash text)
returns jsonb language sql stable security invoker set search_path='' as $$
 select app.pos_order_alert_status(p_installation_id,p_status_secret_hash);
$$;

-- Deliberately separate from the read-only status path. Revocation is allowed
-- after authority expiry/OFF, but only for the current exact secret generation.
create function app.pos_disable_order_alert(p_installation_id uuid,p_status_secret_hash text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
begin
  if p_status_secret_hash is null or p_status_secret_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok',false,'error','unauthorized'); end if;
  update app.pos_order_alert_registrations set enabled=false where installation_id=p_installation_id
    and status_secret_hash=p_status_secret_hash;
  if not found then return jsonb_build_object('ok',false,'error','unauthorized'); end if;
  return jsonb_build_object('ok',true);
end; $$;
create function public.pos_disable_order_alert(p_installation_id uuid,p_status_secret_hash text)
returns jsonb language sql volatile security invoker set search_path='' as $$
 select app.pos_disable_order_alert(p_installation_id,p_status_secret_hash);
$$;

-- Commit-visible receipt/decision ledgers are the outbox; no new trigger can
-- make notification setup/network failure roll back customer submission.
create function app.pos_claim_order_alert_deliveries(p_limit integer default 10)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_now timestamptz:=clock_timestamp(); v_rows jsonb;
begin
  if p_limit is null or p_limit not between 1 and 20 then return jsonb_build_object('ok',false,'error','invalid_request'); end if;
  -- Receipt cutoff is registration-specific; status may restore a still-live
  -- eligible pending set, but fresh pushes never backfill earlier arrivals.
  insert into app.pos_order_alert_deliveries(registration_id,generation,request_id,kind)
  select r.id,r.generation,w.id,'pending' from app.pos_order_alert_registrations r
    join public.web_order_request_events e on e.branch_id=r.branch_id and e.event_type='received'
    join public.web_order_requests w on w.id=e.request_id and w.organization_id=r.organization_id
      and w.restaurant_id=r.restaurant_id and w.branch_id=r.branch_id
    join app.mapsburger_live_web_requests live on live.request_id=w.id
    join app.pos_order_alert_settings s on s.revision=r.setting_revision
    where w.created_at>=s.created_at and app.pos_order_alert_authority(r)>v_now and w.created_at>=r.registered_at
      and w.status='pending' and w.expires_at>v_now
  on conflict do nothing;
  -- Only requests already recorded for this registration can produce a cancel
  -- hint, either from a committed decision or genuine logical deadline expiry.
  insert into app.pos_order_alert_deliveries(registration_id,generation,request_id,kind)
  select d.registration_id,d.generation,d.request_id,'terminal' from app.pos_order_alert_deliveries d
    join app.pos_order_alert_registrations r on r.id=d.registration_id and r.generation=d.generation
    join public.web_order_requests w on w.id=d.request_id
    where d.kind='pending' and app.pos_order_alert_authority(r)>v_now
      and (w.expires_at<=v_now or exists(select 1 from public.web_order_decisions dec where dec.request_id=w.id))
  on conflict do nothing;
  update app.pos_order_alert_deliveries d set state='abandoned',lease_id=null,lease_until=null
    from app.pos_order_alert_registrations r,public.web_order_requests w
    where r.id=d.registration_id and w.id=d.request_id and d.state in ('queued','leased')
      and (r.generation<>d.generation or app.pos_order_alert_authority(r) is null
        or (d.attempt_count>=3 and (d.lease_until is null or d.lease_until<=v_now))
        or (d.kind='pending' and (w.status<>'pending' or w.expires_at<=v_now)));
  with candidates as (
    select d.id from app.pos_order_alert_deliveries d
    join app.pos_order_alert_registrations r on r.id=d.registration_id and r.generation=d.generation
    join public.web_order_requests w on w.id=d.request_id
    where d.state in ('queued','leased') and d.next_attempt_at<=v_now and d.attempt_count<3
      and (d.lease_until is null or d.lease_until<=v_now) and app.pos_order_alert_authority(r)>v_now
      and (d.kind='terminal' or (w.status='pending' and w.expires_at>v_now))
    order by d.created_at,d.id for update of d skip locked limit p_limit
  ), leased as (
    update app.pos_order_alert_deliveries d set state='leased',attempt_count=d.attempt_count+1,
      lease_id=gen_random_uuid(),lease_until=v_now+interval '2 minutes'
    from candidates c where d.id=c.id returning d.*
  ) select coalesce(jsonb_agg(jsonb_build_object('delivery_id',l.id,'lease_id',l.lease_id,
    'registration_id',r.id,'generation',l.generation,'fcm_token',r.fcm_token,'kind',l.kind,
    'request_id',l.request_id,'expires_at',w.expires_at,'authority_expires_at',app.pos_order_alert_authority(r))),'[]')
    into v_rows from leased l join app.pos_order_alert_registrations r on r.id=l.registration_id
    join public.web_order_requests w on w.id=l.request_id;
  return jsonb_build_object('ok',true,'server_time',v_now,'deliveries',v_rows);
end; $$;
create function public.pos_claim_order_alert_deliveries(p_limit integer default 10)
returns jsonb language sql volatile security invoker set search_path='' as $$
 select app.pos_claim_order_alert_deliveries(p_limit);
$$;
create function app.pos_finish_order_alert_delivery(p_delivery_id uuid,p_lease_id uuid,p_outcome text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_delivery app.pos_order_alert_deliveries;
begin
  if p_outcome not in ('sent','retry','invalid_token','permanent_failure') or p_outcome is null then
    return jsonb_build_object('ok',false,'error','invalid_request'); end if;
  select * into v_delivery from app.pos_order_alert_deliveries where id=p_delivery_id for update;
  if not found or v_delivery.state<>'leased' or v_delivery.lease_id is distinct from p_lease_id then
    return jsonb_build_object('ok',false,'error','stale_lease'); end if;
  update app.pos_order_alert_deliveries set state=case when p_outcome='sent' then 'sent'
      when p_outcome='retry' and attempt_count<3 then 'queued' else 'abandoned' end,
    sent_at=case when p_outcome='sent' then clock_timestamp() else null end,
    next_attempt_at=clock_timestamp()+interval '1 minute',lease_id=null,lease_until=null where id=p_delivery_id;
  if p_outcome='invalid_token' then update app.pos_order_alert_registrations set enabled=false
    where id=v_delivery.registration_id and generation=v_delivery.generation; end if;
  return jsonb_build_object('ok',true);
end; $$;
create function public.pos_finish_order_alert_delivery(p_delivery_id uuid,p_lease_id uuid,p_outcome text)
returns jsonb language sql volatile security invoker set search_path='' as $$
 select app.pos_finish_order_alert_delivery(p_delivery_id,p_lease_id,p_outcome);
$$;

-- Gateway/worker-only routines: no anonymous or signed-in application caller.
revoke all on function app.pos_order_alert_status(uuid,text),public.pos_order_alert_status(uuid,text),
 app.pos_disable_order_alert(uuid,text),public.pos_disable_order_alert(uuid,text),
 app.pos_claim_order_alert_deliveries(integer),public.pos_claim_order_alert_deliveries(integer),
 app.pos_finish_order_alert_delivery(uuid,uuid,text),public.pos_finish_order_alert_delivery(uuid,uuid,text)
 from public,anon,authenticated,service_role;
grant execute on function app.pos_order_alert_status(uuid,text),public.pos_order_alert_status(uuid,text),
 app.pos_disable_order_alert(uuid,text),public.pos_disable_order_alert(uuid,text),
 app.pos_claim_order_alert_deliveries(integer),public.pos_claim_order_alert_deliveries(integer),
 app.pos_finish_order_alert_delivery(uuid,uuid,text),public.pos_finish_order_alert_delivery(uuid,uuid,text) to service_role;
