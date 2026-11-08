-- BIZBOT-POS-LONG-SHIFT-ALERTS-001. Dormant until an owner establishes a
-- branch policy AND approves an end on an existing shift. No production default cap.
begin;
create table app.pos_shift_alert_policies (
  branch_id uuid primary key, organization_id uuid not null, restaurant_id uuid not null,
  revision uuid not null default gen_random_uuid(), enabled boolean not null,
  cap_minutes integer, changed_by uuid not null references public.app_users(id),
  foreign key (organization_id,restaurant_id,branch_id) references public.branches(organization_id,restaurant_id,id),
  check ((enabled and cap_minutes>0 and cap_minutes is not null) or (not enabled and cap_minutes is null))
);
create table app.pos_shift_alert_approvals (
  shift_id uuid primary key references public.shifts(id), policy_revision uuid not null,
  approved_until timestamptz not null check(isfinite(approved_until)),
  approved_by uuid not null references public.app_users(id)
);
create table app.pos_shift_alert_consents (
  id uuid primary key, installation_id uuid not null, device_id uuid not null references public.devices(id),
  device_session_id uuid not null references public.device_sessions(id), pin_session_id uuid not null references public.pin_sessions(id),
  employee_id uuid not null references public.employee_profiles(id), membership_id uuid not null references public.memberships(id),
  shift_id uuid not null references app.pos_shift_alert_approvals(shift_id), branch_id uuid not null references app.pos_shift_alert_policies(branch_id),
  policy_revision uuid not null, gate_revision bigint not null references app.pos_order_alert_settings(revision),
  deadline timestamptz not null, issued_at timestamptz not null,
  reserve_until timestamptz not null, revoke_hash text not null check(revoke_hash ~ '^[0-9a-f]{64}$'),
  state text not null check(state in ('pending','active','ended')),
  enrollment_token_hash text, enrollment_status_hash text,
  check(reserve_until<=issued_at+interval '5 minutes' and deadline>issued_at)
);
create index pos_shift_alert_recent_device on app.pos_shift_alert_consents(device_id,issued_at desc);
create index pos_shift_alert_live_branch on app.pos_shift_alert_consents(branch_id) where state<>'ended';
create unique index pos_shift_alert_current_device on app.pos_shift_alert_consents(device_id) where state<>'ended';
create unique index pos_shift_alert_current_install on app.pos_shift_alert_consents(installation_id) where state<>'ended';
create index pos_shift_alert_live_shift on app.pos_shift_alert_consents(shift_id) where state<>'ended';
create index pos_shift_alert_live_membership on app.pos_shift_alert_consents(membership_id) where state<>'ended';
create index pos_shift_alert_live_employee on app.pos_shift_alert_consents(employee_id) where state<>'ended';
create index pos_shift_alert_live_pin on app.pos_shift_alert_consents(pin_session_id) where state<>'ended';
create index pos_shift_alert_live_session on app.pos_shift_alert_consents(device_session_id) where state<>'ended';
create unique index pos_shift_alert_revoke_key on app.pos_shift_alert_consents(installation_id,revoke_hash);
create index pos_shift_alert_previous_status on app.pos_shift_alert_consents(installation_id,enrollment_status_hash)
 where enrollment_status_hash is not null;
alter table app.pos_order_alert_registrations add column duty_consent_id uuid references app.pos_shift_alert_consents(id);
create unique index pos_alert_registration_duty on app.pos_order_alert_registrations(duty_consent_id) where duty_consent_id is not null;
do $$ declare t text; begin
 foreach t in array array['pos_shift_alert_policies','pos_shift_alert_approvals','pos_shift_alert_consents'] loop
   execute format('alter table app.%I enable row level security',t);
   execute format('alter table app.%I force row level security',t);
   execute format('revoke all on app.%I from public,anon,authenticated,service_role',t);
 end loop;
end $$;

-- Exact owner role and verified AAL2 under row locks, independent of client-selected org.
create function app.pos_shift_alert_owner(p_branch uuid) returns uuid
language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=app.current_app_user_id();
begin
 if actor is null or app.current_auth_assurance_level() is distinct from 'aal2' then return null; end if;
 perform 1 from public.branches b join public.restaurants r on r.id=b.restaurant_id and r.organization_id=b.organization_id
 join public.organizations o on o.id=b.organization_id join public.memberships m on m.organization_id=b.organization_id
 join public.app_users u on u.id=m.app_user_id
 where b.id=p_branch and b.status='active' and b.deleted_at is null and r.status='active' and r.deleted_at is null
 and o.status='active' and o.deleted_at is null and u.id=actor and u.is_active and u.auth_user_id=auth.uid()
 and m.role in ('org_owner','restaurant_owner') and m.status='active' and m.deleted_at is null
 and (m.restaurant_id is null or m.restaurant_id=b.restaurant_id) and (m.branch_id is null or m.branch_id=b.id)
 for share of b,r,o,m,u;
 if found then return actor; end if;
 return null;
end $$;
create function app.set_pos_shift_alert_policy(p_branch_id uuid,p_expected_revision uuid,p_enabled jsonb,p_cap_minutes integer)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare actor uuid;pol app.pos_shift_alert_policies;
begin
 if not app.lock_pos_order_alert_writes() then return jsonb_build_object('ok',false,'error','unavailable');end if;
 actor:=app.pos_shift_alert_owner(p_branch_id);
 if actor is null then return jsonb_build_object('ok',false,'error','unauthorized');end if;
 if jsonb_typeof(p_enabled) is distinct from 'boolean' or (p_enabled='true'::jsonb and (p_cap_minutes is null or p_cap_minutes<=0))
 or (p_enabled='false'::jsonb and p_cap_minutes is not null) then return jsonb_build_object('ok',false,'error','invalid_request');end if;
 select * into pol from app.pos_shift_alert_policies where branch_id=p_branch_id for update;
 if pol.revision is distinct from p_expected_revision then return jsonb_build_object('ok',false,'error','stale_policy');end if;
 insert into app.pos_shift_alert_policies(branch_id,organization_id,restaurant_id,enabled,cap_minutes,changed_by)
 select id,organization_id,restaurant_id,p_enabled='true'::jsonb,p_cap_minutes,actor from public.branches where id=p_branch_id
 on conflict(branch_id) do update set revision=gen_random_uuid(),enabled=excluded.enabled,cap_minutes=excluded.cap_minutes,changed_by=actor
 returning * into pol;
 update app.pos_shift_alert_consents set state='ended' where branch_id=p_branch_id and state<>'ended';
 perform app.management_audit(pol.organization_id,pol.restaurant_id,p_branch_id,'pos_alert.shift_policy_changed',null,
  jsonb_build_object('enabled',p_enabled,'cap_minutes',p_cap_minutes,'revision',pol.revision));
 return jsonb_build_object('ok',true,'policy_revision',pol.revision);
end $$;

create function app.approve_pos_shift_alert_end(p_shift_id uuid,p_policy_revision uuid,p_approved_until timestamptz)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare sh public.shifts;actor uuid;pol app.pos_shift_alert_policies;
begin
 if not app.lock_pos_order_alert_writes() then return jsonb_build_object('ok',false,'error','unavailable');end if;
 select * into sh from public.shifts where id=p_shift_id;
 actor:=app.pos_shift_alert_owner(sh.branch_id);
 if actor is null then return jsonb_build_object('ok',false,'error','unauthorized');end if;
 select * into sh from public.shifts where id=p_shift_id for share;
 if app.pos_shift_alert_owner(sh.branch_id) is distinct from actor then return jsonb_build_object('ok',false,'error','unauthorized');end if;
 select * into pol from app.pos_shift_alert_policies where branch_id=sh.branch_id for share;
 if pol.revision is distinct from p_policy_revision or pol.enabled is distinct from true or sh.status<>'open'
 or sh.deleted_at is not null or sh.closed_at is not null or p_approved_until is null or not isfinite(p_approved_until)
 or p_approved_until<=greatest(clock_timestamp(),sh.opened_at) then return jsonb_build_object('ok',false,'error','no_approved_duty');end if;
 insert into app.pos_shift_alert_approvals values(sh.id,pol.revision,p_approved_until,actor)
 on conflict(shift_id) do update set approved_until=excluded.approved_until,policy_revision=excluded.policy_revision,approved_by=actor
 where (pos_shift_alert_approvals.approved_until,pos_shift_alert_approvals.policy_revision)
 is distinct from (excluded.approved_until,excluded.policy_revision);
 if found then
   update app.pos_shift_alert_consents set state='ended' where shift_id=sh.id and state<>'ended';
   perform app.management_audit(sh.organization_id,sh.restaurant_id,sh.branch_id,'pos_alert.shift_end_approved',null,
     jsonb_build_object('shift_id',sh.id,'approved_until',p_approved_until,'revision',pol.revision));
 end if;
 return jsonb_build_object('ok',true,'shift_id',sh.id,'policy_revision',pol.revision,'approved_until',p_approved_until);
end $$;

-- These timestamps are written only by foreground preview/commit. Time passing
-- beyond an otherwise active, unended PIN is distinct from explicit logout.
-- Lock the already token-proven human before the normal context acquires
-- membership/employee locks, in the same order as account management.
create function app.pos_shift_alert_human(p_pin uuid,p_device uuid,p_token text) returns boolean
language plpgsql volatile security definer set search_path='' as $$
begin
 if auth.uid() is null or p_token is null or length(p_token)>4096 then return false;end if;
 perform 1 from public.pin_sessions ps join public.device_sessions ds on ds.id=ps.device_session_id
 join public.memberships m on m.id=ps.resolved_membership_id and m.organization_id=ps.organization_id
 join public.app_users u on u.id=m.app_user_id
 where ps.id=p_pin and ds.device_id=p_device and ds.session_token_ref=app.hash_provisioning_secret(btrim(p_token))
 and u.is_active for share of u;
 return found;
end $$;
create function app.pos_preview_shift_order_alert(p_installation_id uuid,p_device_id uuid,p_pin_session_id uuid,
 p_device_session_token text,p_consent_id uuid,p_revoke_hash text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare ctx jsonb;c app.pos_shift_alert_consents;before_expiry timestamptz;v_now timestamptz;gate app.pos_order_alert_settings;
 sh public.shifts;pol app.pos_shift_alert_policies;a app.pos_shift_alert_approvals;
begin
 if p_consent_id is null or p_installation_id is null or p_revoke_hash is null or p_revoke_hash !~ '^[0-9a-f]{64}$' then
   return jsonb_build_object('ok',false,'error','invalid_request'); end if;
 if not app.lock_pos_order_alert_writes() then return jsonb_build_object('ok',false,'error','unavailable');end if;
 -- Pin the existing session limit before normal foreground proof can refresh its idle window.
 select ds.expires_at into before_expiry from public.pin_sessions ps join public.device_sessions ds on ds.id=ps.device_session_id
 where ps.id=p_pin_session_id and ds.device_id=p_device_id;
 if not app.pos_shift_alert_human(p_pin_session_id,p_device_id,p_device_session_token) then
  return jsonb_build_object('ok',false,'error','unauthorized');end if;
 ctx:=app.pos_web_order_context(p_pin_session_id,p_device_id,p_device_session_token);
 if ctx->'ok' is distinct from 'true'::jsonb or ctx->>'pin_expires_at' is null or before_expiry is null then
  return jsonb_build_object('ok',false,'error','unauthorized'); end if;
 if exists(select 1 from app.pos_order_alert_installation_owners where installation_id=p_installation_id and device_id<>p_device_id)
 then return jsonb_build_object('ok',false,'error','unauthorized'); end if;
 select * into sh from public.shifts where device_id=p_device_id and branch_id=(ctx->>'branch_id')::uuid
 and organization_id=(ctx->>'organization_id')::uuid and restaurant_id=(ctx->>'restaurant_id')::uuid
 and opened_by_employee_profile_id=(ctx->>'employee_profile_id')::uuid and resolved_membership_id=(ctx->>'resolved_membership_id')::uuid
 and status='open' and closed_at is null and deleted_at is null for share;
 select * into pol from app.pos_shift_alert_policies where branch_id=sh.branch_id and enabled for share;
 select * into a from app.pos_shift_alert_approvals where shift_id=sh.id and policy_revision=pol.revision for share;
 select * into gate from app.pos_order_alert_settings order by revision desc limit 1 for share;
 v_now:=clock_timestamp();
 if a.shift_id is null or least(a.approved_until,sh.opened_at+make_interval(mins=>pol.cap_minutes),before_expiry)<=v_now
 or not exists(select 1 from app.online_order_settings where branch_id=sh.branch_id and alerts_enabled)
 or gate.enabled is distinct from true then
   return jsonb_build_object('ok',false,'error','no_approved_duty'); end if;
 update app.pos_shift_alert_consents set state='ended' where (device_id=p_device_id or installation_id=p_installation_id)
   and state<>'ended' and (deadline<=v_now or(state='pending' and reserve_until<=v_now));
 select * into c from app.pos_shift_alert_consents where id=p_consent_id;
 if found then
   if c.state<>'pending' or c.installation_id<>p_installation_id or c.device_id<>p_device_id or c.shift_id<>sh.id
      or c.pin_session_id<>p_pin_session_id or c.policy_revision<>pol.revision or c.gate_revision<>gate.revision or c.revoke_hash<>p_revoke_hash then
     return jsonb_build_object('ok',false,'error','stale_consent'); end if;
 else
   if exists(select 1 from app.pos_shift_alert_consents where state<>'ended' and (device_id=p_device_id or installation_id=p_installation_id))
     or exists(select 1 from app.pos_shift_alert_consents where installation_id=p_installation_id and revoke_hash=p_revoke_hash)
     or (select count(*) from (select 1 from app.pos_shift_alert_consents where device_id=p_device_id and issued_at>v_now-interval '24 hours' limit 24) recent)>=24
     then return jsonb_build_object('ok',false,'error','busy');end if;
   insert into app.pos_shift_alert_consents(id,installation_id,device_id,device_session_id,pin_session_id,employee_id,membership_id,shift_id,
     branch_id,policy_revision,gate_revision,deadline,issued_at,reserve_until,revoke_hash,state)
   values(p_consent_id,p_installation_id,p_device_id,(ctx->>'device_session_id')::uuid,p_pin_session_id,sh.opened_by_employee_profile_id,
     sh.resolved_membership_id,sh.id,sh.branch_id,pol.revision,gate.revision,least(a.approved_until,sh.opened_at+make_interval(mins=>pol.cap_minutes),before_expiry),
     v_now,v_now+interval '5 minutes',p_revoke_hash,'pending') returning * into c;
 end if;
 return jsonb_build_object('ok',true,'mode','shift','consent_id',c.id,'shift_id',c.shift_id,'policy_revision',c.policy_revision,
   'authority_expires_at',c.deadline,'server_time',v_now);
end $$;

-- Reuse the established ownership, token and global/branch gate implementation.
-- Its ordinary 8-hour physical CHECK is unchanged. The separate duty deadline
-- is consulted only for a registration explicitly attached to an active consent.
alter function app.pos_register_order_alert(uuid,text,text,uuid,uuid,text) rename to pos_register_order_alert_core;
alter function app.pos_order_alert_status(uuid,text) rename to pos_order_alert_status_core;
alter function app.pos_disable_order_alert(uuid,text) rename to pos_disable_order_alert_core;
alter function app.pos_refresh_order_alert_token(uuid,text,text,uuid) rename to pos_refresh_order_alert_token_core;
revoke all on function app.pos_register_order_alert_core(uuid,text,text,uuid,uuid,text),
 app.pos_order_alert_status_core(uuid,text),app.pos_disable_order_alert_core(uuid,text),
 app.pos_refresh_order_alert_token_core(uuid,text,text,uuid) from public,anon,authenticated,service_role;

create function app.pos_register_order_alert(p_installation_id uuid,p_fcm_token text,p_status_secret text,
 p_device_id uuid,p_pin_session_id uuid,p_device_session_token text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
 if not app.lock_pos_order_alert_writes() then return jsonb_build_object('ok',false,'error','unavailable');end if;
 -- A legacy call cannot replace a pending/live duty or reuse a duty credential.
 if exists(select 1 from app.pos_shift_alert_consents c where (c.installation_id=p_installation_id or c.device_id=p_device_id)
 and ((c.state='active' and c.deadline>clock_timestamp()) or(c.state='pending' and c.reserve_until>clock_timestamp() and c.deadline>clock_timestamp())
   or c.enrollment_status_hash=encode(sha256(convert_to(p_status_secret,'UTF8')),'hex'))) then
   return jsonb_build_object('ok',false,'error','invalid_request');end if;
 result:=app.pos_register_order_alert_core(p_installation_id,p_fcm_token,p_status_secret,p_device_id,p_pin_session_id,p_device_session_token);
 if result->'ok'='true'::jsonb then
   update app.pos_order_alert_registrations set duty_consent_id=null where id=(result->>'registration_id')::uuid and duty_consent_id is not null;
 end if;
 return result;
end $$;

create function app.pos_register_shift_order_alert(p_installation_id uuid,p_device_id uuid,p_pin_session_id uuid,
 p_device_session_token text,p_consent_id uuid,p_shift_id uuid,p_policy_revision uuid,p_expected_deadline timestamptz,
 p_status_secret text,p_fcm_token text,p_consent jsonb)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare c app.pos_shift_alert_consents;r app.pos_order_alert_registrations;ctx jsonb;reg jsonb;v_now timestamptz;
 token_hash text:=encode(sha256(convert_to(p_fcm_token,'UTF8')),'hex');
 status_hash text:=encode(sha256(convert_to(p_status_secret,'UTF8')),'hex');
begin
 if p_consent is distinct from 'true'::jsonb or p_status_secret is null or p_status_secret !~ '^[0-9a-f]{64}$'
 or p_fcm_token is null or length(p_fcm_token) not between 20 and 4096 or p_fcm_token~'[[:space:][:cntrl:]]' then
   return jsonb_build_object('ok',false,'error','invalid_request');end if;
 if not app.lock_pos_order_alert_writes() then return jsonb_build_object('ok',false,'error','unavailable');end if;
 if not app.pos_shift_alert_human(p_pin_session_id,p_device_id,p_device_session_token) then
  return jsonb_build_object('ok',false,'error','unauthorized');end if;
 ctx:=app.pos_web_order_context(p_pin_session_id,p_device_id,p_device_session_token);
 if ctx->'ok' is distinct from 'true'::jsonb then return jsonb_build_object('ok',false,'error','unauthorized');end if;
 perform 1 from public.shifts sh join app.pos_shift_alert_policies pol on pol.branch_id=sh.branch_id
 join app.pos_shift_alert_approvals a on a.shift_id=sh.id and a.policy_revision=pol.revision
 where sh.id=p_shift_id and sh.device_id=p_device_id and sh.closed_at is null and sh.deleted_at is null and sh.status='open'
 and sh.branch_id=(ctx->>'branch_id')::uuid and sh.opened_by_employee_profile_id=(ctx->>'employee_profile_id')::uuid
 and sh.resolved_membership_id=(ctx->>'resolved_membership_id')::uuid and pol.enabled and pol.revision=p_policy_revision
 and least(a.approved_until,sh.opened_at+make_interval(mins=>pol.cap_minutes),(ctx->>'session_expires_at')::timestamptz)>=p_expected_deadline
 for share of sh,pol,a;
 if not found then return jsonb_build_object('ok',false,'error','stale_consent');end if;
 select * into c from app.pos_shift_alert_consents where id=p_consent_id for update;
 v_now:=clock_timestamp();
 if not found or c.state='ended' or(c.state='pending' and c.reserve_until<=v_now) or c.deadline<=v_now
 or (c.installation_id,c.device_id,c.pin_session_id,c.device_session_id,c.shift_id,c.policy_revision,c.deadline)
 is distinct from(p_installation_id,p_device_id,p_pin_session_id,(ctx->>'device_session_id')::uuid,p_shift_id,p_policy_revision,p_expected_deadline)
 or c.gate_revision is distinct from (select revision from app.pos_order_alert_settings order by revision desc limit 1)
 or c.revoke_hash=status_hash then return jsonb_build_object('ok',false,'error','stale_consent');end if;
 if c.state='active' then
   select * into r from app.pos_order_alert_registrations where duty_consent_id=c.id and enabled and retired_at is null;
   if not found or app.pos_order_alert_authority(r) is null or c.enrollment_status_hash<>status_hash or c.enrollment_token_hash<>token_hash
   then return jsonb_build_object('ok',false,'error','stale_consent');end if;
 else
   -- Per-consent status material must never be a replay of a different activation.
   if exists(select 1 from app.pos_shift_alert_consents previous where previous.installation_id=p_installation_id
     and previous.enrollment_status_hash=status_hash) or exists(select 1 from app.pos_order_alert_registrations previous
     where previous.installation_id=p_installation_id and previous.status_secret_hash=status_hash) then
     return jsonb_build_object('ok',false,'error','invalid_request');end if;
   reg:=app.pos_register_order_alert_core(p_installation_id,p_fcm_token,p_status_secret,p_device_id,p_pin_session_id,p_device_session_token);
   if reg->'ok' is distinct from 'true'::jsonb then return jsonb_build_object('ok',false,'error','unavailable');end if;
   -- Nothing after the core commit may return a partial ordinary authority.
   if c.deadline<=clock_timestamp() or c.reserve_until<=clock_timestamp() then raise exception 'stale';end if;
   update app.pos_order_alert_registrations set duty_consent_id=c.id,registered_at=refreshed_at where id=(reg->>'registration_id')::uuid returning * into strict r;
   update app.pos_shift_alert_consents set state='active',enrollment_status_hash=status_hash,enrollment_token_hash=token_hash where id=c.id;
 end if;
 return jsonb_build_object('ok',true,'mode','shift','consent_id',c.id,'shift_id',c.shift_id,'policy_revision',c.policy_revision,
  'authority_expires_at',c.deadline,'server_time',clock_timestamp(),'registration_id',r.id,'generation',r.generation);
exception when others or query_canceled then return jsonb_build_object('ok',false,'error','unavailable');
end $$;

create or replace function app.pos_order_alert_authority(p_registration app.pos_order_alert_registrations)
returns timestamptz language sql stable security definer set search_path='' as $$
 select case when p_registration.duty_consent_id is null then least(p_registration.authority_expires_at,ds.expires_at,ps.expires_at)
             else least(c.deadline,ds.expires_at) end
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
 left join app.pos_shift_alert_consents c on c.id=p_registration.duty_consent_id
 left join app.pos_shift_alert_policies pol on pol.branch_id=c.branch_id
 left join app.pos_shift_alert_approvals a on a.shift_id=c.shift_id
 left join public.shifts sh on sh.id=c.shift_id
 where p_registration.retired_at is null
   and exists(select 1 from app.pos_order_alert_installation_owners own where own.installation_id=p_registration.installation_id
     and own.device_id=p_registration.device_id and own.organization_id=p_registration.organization_id
     and own.restaurant_id=p_registration.restaurant_id and own.branch_id=p_registration.branch_id)
   and p_registration.enabled
   and ((p_registration.duty_consent_id is null and p_registration.authority_expires_at>statement_timestamp()
     and ps.expires_at>statement_timestamp()) or
     (c.state='active' and c.deadline>statement_timestamp() and c.installation_id=p_registration.installation_id
      and c.pin_session_id=ps.id and c.device_session_id=ds.id and c.membership_id=m.id and c.employee_id=ep.id
      and c.device_id=d.id and c.branch_id=b.id and pol.enabled and pol.revision=c.policy_revision
      and a.policy_revision=c.policy_revision and a.approved_until>=c.deadline and ps.expires_at is not null
      and exists(select 1 from public.app_users u where u.id=m.app_user_id and u.is_active)
      and sh.status='open' and sh.closed_at is null and sh.deleted_at is null and sh.device_id=d.id
      and sh.opened_at+make_interval(mins=>pol.cap_minutes)>=c.deadline
      and sh.opened_by_employee_profile_id=ep.id and sh.resolved_membership_id=m.id))
   and s.enabled and s.revision=(select max(revision) from app.pos_order_alert_settings)
   and ds.id=p_registration.device_session_id and d.id=p_registration.device_id
   and ps.employee_profile_id=p_registration.employee_profile_id and ps.resolved_membership_id=p_registration.resolved_membership_id
   and ds.is_active and ds.revoked_at is null and ds.expires_at>statement_timestamp()
   and d.device_type='pos' and d.is_active and d.deleted_at is null
   and dp.status='active' and dp.revoked_at is null and dp.deleted_at is null
   and ps.is_active and ps.ended_at is null
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

-- V1 service calls never consume the credentials of a duty registration.
create function app.pos_order_alert_status(p_installation_id uuid,p_status_secret_hash text)
returns jsonb language sql stable security definer set search_path='' as $$
 select case when exists(select 1 from app.pos_order_alert_registrations where installation_id=p_installation_id and retired_at is null and duty_consent_id is not null)
   then jsonb_build_object('ok',false,'error','unauthorized') else app.pos_order_alert_status_core(p_installation_id,p_status_secret_hash) end;
$$;
create function app.pos_disable_order_alert(p_installation_id uuid,p_status_secret_hash text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
begin
 if not app.lock_pos_order_alert_writes() then return jsonb_build_object('ok',false,'error','unavailable');end if;
 if exists(select 1 from app.pos_order_alert_registrations where installation_id=p_installation_id and retired_at is null and duty_consent_id is not null)
 then return jsonb_build_object('ok',false,'error','unauthorized');end if;
 return app.pos_disable_order_alert_core(p_installation_id,p_status_secret_hash);
end $$;
create function app.pos_refresh_order_alert_token(p_installation_id uuid,p_status_secret_hash text,p_fcm_token text,p_expected_generation uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
begin
 if not app.lock_pos_order_alert_writes() then return jsonb_build_object('ok',false,'error','unavailable');end if;
 if exists(select 1 from app.pos_order_alert_registrations where installation_id=p_installation_id and retired_at is null and duty_consent_id is not null)
 then return jsonb_build_object('ok',false,'error','unauthorized');end if;
 return app.pos_refresh_order_alert_token_core(p_installation_id,p_status_secret_hash,p_fcm_token,p_expected_generation);
end $$;

create function app.pos_shift_order_alert_status(p_installation_id uuid,p_consent_id uuid,p_status_secret_hash text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r app.pos_order_alert_registrations;result jsonb;
begin
 select * into r from app.pos_order_alert_registrations where installation_id=p_installation_id and retired_at is null
   and duty_consent_id=p_consent_id and status_secret_hash=p_status_secret_hash;
 if not found then return jsonb_build_object('ok',false,'error','unauthorized');end if;
 result:=app.pos_order_alert_status_core(p_installation_id,p_status_secret_hash);
 if result->'ok'='true'::jsonb then result:=result||jsonb_build_object('consent_id',p_consent_id,'generation',r.generation);end if;
 return result;
end $$;

create function app.pos_refresh_shift_order_alert_token(p_installation_id uuid,p_consent_id uuid,p_status_secret_hash text,
 p_fcm_token text,p_expected_generation uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;
begin
 if not app.lock_pos_order_alert_writes() then return jsonb_build_object('ok',false,'error','unavailable');end if;
 if not exists(select 1 from app.pos_order_alert_registrations where installation_id=p_installation_id and retired_at is null
   and duty_consent_id=p_consent_id and status_secret_hash=p_status_secret_hash and generation=p_expected_generation)
 then return jsonb_build_object('ok',false,'error','unauthorized');end if;
 result:=app.pos_refresh_order_alert_token_core(p_installation_id,p_status_secret_hash,p_fcm_token,p_expected_generation);
 if result->'ok'='true'::jsonb then result:=result||jsonb_build_object('consent_id',p_consent_id,'server_time',clock_timestamp());end if;
 return result;
end $$;

create function app.pos_revoke_shift_order_alert(p_installation_id uuid,p_consent_id uuid,p_revoke_hash text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
begin
 if not app.lock_pos_order_alert_writes() then return jsonb_build_object('ok',false,'error','unavailable');end if;
 perform 1 from app.pos_shift_alert_consents where id=p_consent_id and installation_id=p_installation_id and revoke_hash=p_revoke_hash for update;
 if not found then return jsonb_build_object('ok',false,'error','unauthorized');end if;
 update app.pos_shift_alert_consents set state='ended' where id=p_consent_id and state<>'ended';
 update app.pos_order_alert_registrations set enabled=false where duty_consent_id=p_consent_id and enabled;
 return jsonb_build_object('ok',true,'consent_id',p_consent_id);
end $$;


-- A privileged claim may expose only the live consent attached to its exact
-- leased delivery generation. Keep the legacy payload shape byte-for-field.
alter function app.pos_claim_order_alert_deliveries(integer) rename to pos_claim_order_alert_deliveries_core;
revoke all on function app.pos_claim_order_alert_deliveries_core(integer) from public,anon,authenticated,service_role;
create function app.pos_claim_order_alert_deliveries(p_limit integer default 10)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare result jsonb;payload jsonb;
begin
 result:=app.pos_claim_order_alert_deliveries_core(p_limit);
 if result->'ok' is distinct from 'true'::jsonb then return result;end if;
 select coalesce(jsonb_agg(case when r.duty_consent_id is null then item
   else item||jsonb_build_object('consent_id',r.duty_consent_id) end order by ord),'[]'::jsonb) into payload
 from jsonb_array_elements(result->'deliveries') with ordinality x(item,ord)
 join app.pos_order_alert_registrations r on r.id=(item->>'registration_id')::uuid
   and r.generation=(item->>'generation')::uuid and app.pos_order_alert_authority(r)>clock_timestamp();
 return jsonb_set(result,'{deliveries}',payload);
end $$;

-- Synchronous termination on a rights/identity/shift transition. A subsequent
-- re-enable in the same or a later transaction cannot revive either pending or
-- active consent. Avoid broad scans: live registration count is at most one per device.
create function app.end_pos_shift_alert_bindings() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if TG_TABLE_NAME='shifts' then
   update app.pos_shift_alert_consents set state='ended' where shift_id=old.id and state<>'ended';
 elsif TG_TABLE_NAME='memberships' then
   update app.pos_shift_alert_consents set state='ended' where membership_id=old.id and state<>'ended';
 elsif TG_TABLE_NAME='employee_profiles' then
   update app.pos_shift_alert_consents set state='ended' where employee_id=old.id and state<>'ended';
 elsif TG_TABLE_NAME='pin_sessions' then
   update app.pos_shift_alert_consents set state='ended' where pin_session_id=old.id and state<>'ended';
 elsif TG_TABLE_NAME='devices' then
   update app.pos_shift_alert_consents set state='ended' where device_id=old.id and state<>'ended';
 elsif TG_TABLE_NAME='device_sessions' then
   update app.pos_shift_alert_consents set state='ended' where device_session_id=old.id and state<>'ended';
 elsif TG_TABLE_NAME='device_pairings' then
   update app.pos_shift_alert_consents c set state='ended' from public.device_sessions ds
    where c.device_session_id=ds.id and ds.device_pairing_id=old.id and c.state<>'ended';
 elsif TG_TABLE_NAME='online_order_settings' then
   update app.pos_shift_alert_consents set state='ended' where branch_id=old.branch_id and state<>'ended';
 elsif TG_TABLE_NAME='app_users' then
   update app.pos_shift_alert_consents c set state='ended' from public.memberships m
    where m.app_user_id=old.id and c.membership_id=m.id and c.state<>'ended';
 elsif TG_TABLE_NAME='branches' then
   update app.pos_shift_alert_consents set state='ended' where branch_id=old.id and state<>'ended';
 elsif TG_TABLE_NAME='restaurants' then
   update app.pos_shift_alert_consents c set state='ended' from app.pos_shift_alert_policies p
    where p.restaurant_id=old.id and c.branch_id=p.branch_id and c.state<>'ended';
 elsif TG_TABLE_NAME='organizations' then
   update app.pos_shift_alert_consents c set state='ended' from app.pos_shift_alert_policies p
    where p.organization_id=old.id and c.branch_id=p.branch_id and c.state<>'ended';
 end if;
 return null;
end $$;
create trigger end_shift_alert_on_shift after update on public.shifts for each row when
 ((old.status,old.closed_at,old.deleted_at,old.opened_by_employee_profile_id,old.resolved_membership_id,old.device_id,old.opened_at)
 is distinct from(new.status,new.closed_at,new.deleted_at,new.opened_by_employee_profile_id,new.resolved_membership_id,new.device_id,new.opened_at))
 execute function app.end_pos_shift_alert_bindings();
create trigger end_shift_alert_on_role after update on public.memberships for each row when
 ((old.role,old.status,old.deleted_at,old.app_user_id,old.organization_id,old.restaurant_id,old.branch_id)
 is distinct from(new.role,new.status,new.deleted_at,new.app_user_id,new.organization_id,new.restaurant_id,new.branch_id))
 execute function app.end_pos_shift_alert_bindings();
create trigger end_shift_alert_on_employee after update on public.employee_profiles for each row when
 ((old.employment_status,old.deleted_at,old.membership_id,old.app_user_id,old.organization_id,old.restaurant_id,old.branch_id)
 is distinct from(new.employment_status,new.deleted_at,new.membership_id,new.app_user_id,new.organization_id,new.restaurant_id,new.branch_id))
 execute function app.end_pos_shift_alert_bindings();
create trigger end_shift_alert_on_pin after update on public.pin_sessions for each row when
 ((old.is_active,old.ended_at,old.employee_profile_id,old.resolved_membership_id,old.device_session_id)
 is distinct from(new.is_active,new.ended_at,new.employee_profile_id,new.resolved_membership_id,new.device_session_id))
 execute function app.end_pos_shift_alert_bindings();
create trigger end_shift_alert_on_device after update on public.devices for each row when
 ((old.is_active,old.deleted_at,old.device_type) is distinct from(new.is_active,new.deleted_at,new.device_type))
 execute function app.end_pos_shift_alert_bindings();
create trigger end_shift_alert_on_session after update on public.device_sessions for each row when
 ((old.is_active,old.revoked_at,old.device_pairing_id) is distinct from(new.is_active,new.revoked_at,new.device_pairing_id)
   or (old.expires_at is not null and (new.expires_at is null or new.expires_at<old.expires_at)))
 execute function app.end_pos_shift_alert_bindings();
create trigger end_shift_alert_on_pairing after update on public.device_pairings for each row when
 ((old.status,old.revoked_at,old.deleted_at,old.device_id) is distinct from(new.status,new.revoked_at,new.deleted_at,new.device_id))
 execute function app.end_pos_shift_alert_bindings();
create trigger end_shift_alert_on_online_policy after update on app.online_order_settings for each row when
 (old.alerts_enabled is distinct from new.alerts_enabled) execute function app.end_pos_shift_alert_bindings();
create trigger end_shift_alert_on_person after update on public.app_users for each row when
 ((old.is_active,old.auth_user_id) is distinct from(new.is_active,new.auth_user_id)) execute function app.end_pos_shift_alert_bindings();
create trigger end_shift_alert_on_branch after update on public.branches for each row when
 ((old.status,old.deleted_at,old.restaurant_id,old.organization_id) is distinct from(new.status,new.deleted_at,new.restaurant_id,new.organization_id))
 execute function app.end_pos_shift_alert_bindings();
create trigger end_shift_alert_on_restaurant after update on public.restaurants for each row when
 ((old.status,old.deleted_at,old.organization_id) is distinct from(new.status,new.deleted_at,new.organization_id))
 execute function app.end_pos_shift_alert_bindings();
create trigger end_shift_alert_on_organization after update on public.organizations for each row when
 ((old.status,old.deleted_at) is distinct from(new.status,new.deleted_at)) execute function app.end_pos_shift_alert_bindings();


create function public.set_pos_shift_alert_policy(p_branch_id uuid,p_expected_revision uuid,p_enabled jsonb,p_cap_minutes integer)
returns jsonb language sql volatile security invoker set search_path='' as $$
 select app.set_pos_shift_alert_policy(p_branch_id,p_expected_revision,p_enabled,p_cap_minutes);
$$;
revoke all on function public.set_pos_shift_alert_policy(uuid,uuid,jsonb,integer),app.set_pos_shift_alert_policy(uuid,uuid,jsonb,integer) from public,anon,authenticated,service_role;
grant execute on function public.set_pos_shift_alert_policy(uuid,uuid,jsonb,integer),app.set_pos_shift_alert_policy(uuid,uuid,jsonb,integer) to authenticated;

create function public.approve_pos_shift_alert_end(p_shift_id uuid,p_policy_revision uuid,p_approved_until timestamptz)
returns jsonb language sql volatile security invoker set search_path='' as $$
 select app.approve_pos_shift_alert_end(p_shift_id,p_policy_revision,p_approved_until);
$$;
revoke all on function public.approve_pos_shift_alert_end(uuid,uuid,timestamptz),app.approve_pos_shift_alert_end(uuid,uuid,timestamptz) from public,anon,authenticated,service_role;
grant execute on function public.approve_pos_shift_alert_end(uuid,uuid,timestamptz),app.approve_pos_shift_alert_end(uuid,uuid,timestamptz) to authenticated;

create function public.pos_preview_shift_order_alert(p_installation_id uuid,p_device_id uuid,p_pin_session_id uuid,p_device_session_token text,p_consent_id uuid,p_revoke_hash text)
returns jsonb language sql volatile security invoker set search_path='' as $$
 select app.pos_preview_shift_order_alert(p_installation_id,p_device_id,p_pin_session_id,p_device_session_token,p_consent_id,p_revoke_hash);
$$;
revoke all on function public.pos_preview_shift_order_alert(uuid,uuid,uuid,text,uuid,text),app.pos_preview_shift_order_alert(uuid,uuid,uuid,text,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.pos_preview_shift_order_alert(uuid,uuid,uuid,text,uuid,text),app.pos_preview_shift_order_alert(uuid,uuid,uuid,text,uuid,text) to authenticated;

create function public.pos_register_shift_order_alert(p_installation_id uuid,p_device_id uuid,p_pin_session_id uuid,p_device_session_token text,p_consent_id uuid,p_shift_id uuid,p_policy_revision uuid,p_expected_deadline timestamptz,p_status_secret text,p_fcm_token text,p_consent jsonb)
returns jsonb language sql volatile security invoker set search_path='' as $$
 select app.pos_register_shift_order_alert(p_installation_id,p_device_id,p_pin_session_id,p_device_session_token,p_consent_id,p_shift_id,p_policy_revision,p_expected_deadline,p_status_secret,p_fcm_token,p_consent);
$$;
revoke all on function public.pos_register_shift_order_alert(uuid,uuid,uuid,text,uuid,uuid,uuid,timestamptz,text,text,jsonb),app.pos_register_shift_order_alert(uuid,uuid,uuid,text,uuid,uuid,uuid,timestamptz,text,text,jsonb) from public,anon,authenticated,service_role;
grant execute on function public.pos_register_shift_order_alert(uuid,uuid,uuid,text,uuid,uuid,uuid,timestamptz,text,text,jsonb),app.pos_register_shift_order_alert(uuid,uuid,uuid,text,uuid,uuid,uuid,timestamptz,text,text,jsonb) to authenticated;

create function public.pos_shift_order_alert_status(p_installation_id uuid,p_consent_id uuid,p_status_secret_hash text)
returns jsonb language sql stable security invoker set search_path='' as $$
 select app.pos_shift_order_alert_status(p_installation_id,p_consent_id,p_status_secret_hash);
$$;
revoke all on function public.pos_shift_order_alert_status(uuid,uuid,text),app.pos_shift_order_alert_status(uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.pos_shift_order_alert_status(uuid,uuid,text),app.pos_shift_order_alert_status(uuid,uuid,text) to service_role;

create function public.pos_refresh_shift_order_alert_token(p_installation_id uuid,p_consent_id uuid,p_status_secret_hash text,p_fcm_token text,p_expected_generation uuid)
returns jsonb language sql volatile security invoker set search_path='' as $$
 select app.pos_refresh_shift_order_alert_token(p_installation_id,p_consent_id,p_status_secret_hash,p_fcm_token,p_expected_generation);
$$;
revoke all on function public.pos_refresh_shift_order_alert_token(uuid,uuid,text,text,uuid),app.pos_refresh_shift_order_alert_token(uuid,uuid,text,text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.pos_refresh_shift_order_alert_token(uuid,uuid,text,text,uuid),app.pos_refresh_shift_order_alert_token(uuid,uuid,text,text,uuid) to service_role;

create function public.pos_revoke_shift_order_alert(p_installation_id uuid,p_consent_id uuid,p_revoke_hash text)
returns jsonb language sql volatile security invoker set search_path='' as $$
 select app.pos_revoke_shift_order_alert(p_installation_id,p_consent_id,p_revoke_hash);
$$;
revoke all on function public.pos_revoke_shift_order_alert(uuid,uuid,text),app.pos_revoke_shift_order_alert(uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.pos_revoke_shift_order_alert(uuid,uuid,text),app.pos_revoke_shift_order_alert(uuid,uuid,text) to service_role;

revoke all on function app.pos_shift_alert_owner(uuid),app.pos_shift_alert_human(uuid,uuid,text),app.end_pos_shift_alert_bindings(),
 app.pos_register_order_alert(uuid,text,text,uuid,uuid,text),app.pos_order_alert_status(uuid,text),
 app.pos_disable_order_alert(uuid,text),app.pos_refresh_order_alert_token(uuid,text,text,uuid),app.pos_claim_order_alert_deliveries(integer)
 from public,anon,authenticated,service_role;
grant execute on function app.pos_register_order_alert(uuid,text,text,uuid,uuid,text) to authenticated;
grant execute on function app.pos_order_alert_status(uuid,text),app.pos_disable_order_alert(uuid,text),
 app.pos_refresh_order_alert_token(uuid,text,text,uuid),app.pos_claim_order_alert_deliveries(integer) to service_role;
commit;
