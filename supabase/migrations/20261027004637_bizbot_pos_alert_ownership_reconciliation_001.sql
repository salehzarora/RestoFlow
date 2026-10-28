-- BIZBOT-POS-ALERT-OWNERSHIP-RECONCILIATION-001.
-- An administrator approves an exact relationship, not a capability transfer.
-- Only the next ordinary, freshly authorized v70 foreground registration may
-- consume that five-minute approval. No registration or delivery is deleted.
begin;

-- All alert writers take this lock BEFORE device/context or registration locks.
-- Device-session core writers retain their established hierarchy unchanged.
create function app.lock_pos_order_alert_writes()
returns boolean language plpgsql volatile security invoker set search_path='' set lock_timeout='1s' as $$
begin
 perform pg_catalog.pg_advisory_xact_lock(20261027,36670);
 return true;
exception when others or query_canceled then
 -- A bounded global-lock wait must not emit a statement/parameter error. This
 -- is only the lock wait limit, not a cap on transaction or network duration.
 return false;
end;
$$;
revoke all on function app.lock_pos_order_alert_writes() from public,anon,authenticated,service_role;

alter table app.pos_order_alert_registrations add column retired_at timestamptz;
alter table app.pos_order_alert_registrations add constraint pos_order_alert_retired_disabled
 check(retired_at is null or not enabled);
alter table app.pos_order_alert_registrations drop constraint pos_order_alert_registrations_installation_id_key;
create unique index pos_order_alert_one_current_installation
 on app.pos_order_alert_registrations(installation_id) where retired_at is null;

-- A reservation survives disabled/retired registrations. Vacating the current
-- registration must never let an old foreground credential reclaim ownership.
create table app.pos_order_alert_installation_owners (
 installation_id uuid primary key,
 organization_id uuid not null,
 restaurant_id uuid not null,
 branch_id uuid not null,
 device_id uuid not null,
 ownership_version bigint not null default 1 check(ownership_version>0),
 updated_at timestamptz not null default clock_timestamp(),
 foreign key(organization_id,restaurant_id,branch_id,device_id)
  references public.devices(organization_id,restaurant_id,branch_id,id)
);
insert into app.pos_order_alert_installation_owners(installation_id,organization_id,restaurant_id,branch_id,device_id)
 select installation_id,organization_id,restaurant_id,branch_id,device_id
 from app.pos_order_alert_registrations;

create table app.pos_order_alert_reconciliation_approvals (
 id uuid primary key default gen_random_uuid(),
 client_request_id uuid not null,
 approved_by_app_user_id uuid not null references public.app_users(id),
 approved_by_auth_user_id uuid not null references auth.users(id),
 old_membership_id uuid not null references public.memberships(id),
 current_membership_id uuid not null references public.memberships(id),
 installation_id uuid not null references app.pos_order_alert_installation_owners(installation_id),
 old_registration_id uuid not null references app.pos_order_alert_registrations(id),
 expected_old_generation uuid not null,
 old_device_id uuid not null references public.devices(id),
 current_device_id uuid not null references public.devices(id),
 current_device_session_id uuid not null references public.device_sessions(id),
 current_pin_session_id uuid not null references public.pin_sessions(id),
 organization_id uuid not null,
 old_restaurant_id uuid not null,
 old_branch_id uuid not null,
 current_restaurant_id uuid not null,
 current_branch_id uuid not null,
 expected_ownership_version bigint not null check(expected_ownership_version>0),
 created_at timestamptz not null,
 expires_at timestamptz not null,
 consumed_at timestamptz,
 new_registration_id uuid references app.pos_order_alert_registrations(id),
 unique(approved_by_app_user_id,client_request_id),
 check(old_device_id<>current_device_id),
 check(expires_at>created_at and expires_at<=created_at+interval '5 minutes'),
 check((consumed_at is null)=(new_registration_id is null))
);
create index pos_order_alert_reconciliation_pending
 on app.pos_order_alert_reconciliation_approvals(installation_id,current_device_id,expires_at)
 where consumed_at is null;
do $$ declare t text; begin
 foreach t in array array['pos_order_alert_installation_owners','pos_order_alert_reconciliation_approvals'] loop
  execute format('alter table app.%I enable row level security',t);
  execute format('alter table app.%I force row level security',t);
  execute format('create policy deny_client on app.%I for all to authenticated using(false) with check(false)',t);
  execute format('revoke all on app.%I from public,anon,authenticated,service_role',t);
 end loop;
end; $$;

-- This takes the approved HUMAN actor as a private, already validated reference.
-- It never substitutes a GUC/JWT or treats the anonymous POS principal as admin.
-- Locking the person before memberships follows the management-writer order.
create function app.pos_alert_reconciliation_admin_valid(p_approval app.pos_order_alert_reconciliation_approvals)
returns boolean language plpgsql volatile security definer set search_path='' as $$
declare v_user public.app_users;v_old public.memberships;v_current public.memberships;
begin
 select * into v_user from public.app_users where id=p_approval.approved_by_app_user_id for share;
 if not found or not v_user.is_active or v_user.auth_user_id is distinct from p_approval.approved_by_auth_user_id then return false;end if;
 perform 1 from public.memberships where id in(p_approval.old_membership_id,p_approval.current_membership_id) order by id for share;
 select * into v_old from public.memberships where id=p_approval.old_membership_id;
 if not found then return false;end if;
 select * into v_current from public.memberships where id=p_approval.current_membership_id;
 if not found then return false;end if;
 return v_old.app_user_id=v_user.id and v_current.app_user_id=v_user.id
  and v_old.organization_id=p_approval.organization_id and v_current.organization_id=p_approval.organization_id
  and v_old.status='active' and v_old.deleted_at is null and v_current.status='active' and v_current.deleted_at is null
  and app.role_rank(v_old.role)>=2 and app.role_rank(v_current.role)>=2
  and (v_old.restaurant_id is null or v_old.restaurant_id=p_approval.old_restaurant_id)
  and (v_old.branch_id is null or v_old.branch_id=p_approval.old_branch_id)
  and (v_current.restaurant_id is null or v_current.restaurant_id=p_approval.current_restaurant_id)
  and (v_current.branch_id is null or v_current.branch_id=p_approval.current_branch_id);
end; $$;
revoke all on function app.pos_alert_reconciliation_admin_valid(app.pos_order_alert_reconciliation_approvals)
 from public,anon,authenticated,service_role;

-- An administratively retired owner must not be taken over while its identity,
-- pairing or an unexpired session is still usable. Expiry itself grants nothing.
create function app.pos_alert_old_owner_retired(p_device_id uuid)
returns boolean language plpgsql volatile security definer set search_path='' as $$
declare d public.devices;
begin
 select * into d from public.devices where id=p_device_id for share;
 if not found then return false;end if;
 perform 1 from public.device_pairings where device_id=d.id order by id for share;
 perform 1 from public.device_sessions where device_id=d.id order by id for share;
 return not(d.is_active and d.deleted_at is null)
  and not exists(select 1 from public.device_pairings p where p.device_id=d.id and p.status='active' and p.revoked_at is null and p.deleted_at is null)
  and not exists(select 1 from public.device_sessions s where s.device_id=d.id and s.is_active and s.revoked_at is null
   and (s.expires_at is null or s.expires_at>clock_timestamp()));
end; $$;
revoke all on function app.pos_alert_old_owner_retired(uuid) from public,anon,authenticated,service_role;

create function app.approve_pos_alert_installation_reconciliation(
 p_client_request_id uuid,p_old_registration_id uuid,p_expected_old_generation uuid,p_expected_old_device_id uuid,
 p_current_device_id uuid,p_current_pin_session_id uuid,
 p_expected_current_device_session_id uuid,p_approve_old_to_current boolean)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=app.current_app_user_id();principal uuid:=auth.uid();old app.pos_order_alert_registrations;
 owner app.pos_order_alert_installation_owners;current_device public.devices;a app.pos_order_alert_reconciliation_approvals;
 ds public.device_sessions;pairing public.device_pairings;pin public.pin_sessions;
 fp text;replay jsonb;result jsonb;v_now timestamptz;
begin
 if actor is null or principal is null then return jsonb_build_object('ok',false,'error','permission_denied');end if;
 -- D-006: an ownership approval is a sensitive manager/owner action. Require
 -- verified request assurance before replay, locks or writes, independently of
 -- any selected-organization GUC. POS consumption remains its normal device /
 -- PIN flow; it rechecks the live human authority of this five-minute approval.
 if app.current_auth_assurance_level() is distinct from 'aal2' then
  return jsonb_build_object('ok',false,'error','mfa_required');end if;
 if p_client_request_id is null or p_old_registration_id is null or p_expected_old_generation is null
  or p_expected_old_device_id is null or p_current_device_id is null or p_current_pin_session_id is null
  or p_expected_current_device_session_id is null or p_approve_old_to_current is distinct from true
  or p_current_device_id=p_expected_old_device_id then return jsonb_build_object('ok',false,'error','invalid_request');end if;
 if not app.lock_pos_order_alert_writes() then return jsonb_build_object('ok',false,'error','unavailable');end if;
 select * into old from app.pos_order_alert_registrations where id=p_old_registration_id;
 select * into current_device from public.devices where id=p_current_device_id;
 if old.id is null or current_device.id is null or old.organization_id<>current_device.organization_id
  or app.actor_rank_in_scope(old.organization_id,old.restaurant_id,old.branch_id)<2
  or app.actor_rank_in_scope(current_device.organization_id,current_device.restaurant_id,current_device.branch_id)<2 then
  return jsonb_build_object('ok',false,'error','permission_denied');end if;
 -- Approval is an administrative INTENT, never notification authority. It uses
 -- authorized live relationship IDs and does not export a v70 device secret.
 -- The actual transfer still requires its ordinary fresh device/PIN proof.
 -- Acquire the same hierarchy used by a normal context before person locks.
 perform 1 from public.organizations where id=old.organization_id and status='active' and deleted_at is null for share;
 if not found then return jsonb_build_object('ok',false,'error','permission_denied');end if;
 perform 1 from public.restaurants where organization_id=old.organization_id
   and id in(old.restaurant_id,current_device.restaurant_id) order by id for share;
 perform 1 from public.branches where organization_id=old.organization_id
   and id in(old.branch_id,current_device.branch_id) order by id for share;
 select * into current_device from public.devices where id=p_current_device_id for no key update;
 select * into ds from public.device_sessions where id=p_expected_current_device_session_id and device_id=current_device.id;
 if not found then return jsonb_build_object('ok',false,'error','invalid_session');end if;
 select * into pairing from public.device_pairings where id=ds.device_pairing_id and device_id=current_device.id for no key update;
 if not found then return jsonb_build_object('ok',false,'error','invalid_session');end if;
 select * into ds from public.device_sessions where id=p_expected_current_device_session_id
   and device_id=current_device.id and device_pairing_id=pairing.id for no key update;
 if not found or not current_device.is_active or current_device.deleted_at is not null or current_device.device_type<>'pos'
   or current_device.organization_id<>old.organization_id or ds.organization_id<>current_device.organization_id
   or ds.restaurant_id<>current_device.restaurant_id or ds.branch_id<>current_device.branch_id
   or pairing.organization_id<>current_device.organization_id or pairing.restaurant_id<>current_device.restaurant_id
   or pairing.branch_id<>current_device.branch_id or pairing.status<>'active' or pairing.deleted_at is not null or pairing.revoked_at is not null
   or not ds.is_active or ds.revoked_at is not null or ds.expires_at is null or ds.expires_at<=clock_timestamp() then
   return jsonb_build_object('ok',false,'error','invalid_session');end if;
 a.approved_by_app_user_id:=actor;a.approved_by_auth_user_id:=principal;a.organization_id:=old.organization_id;
 a.old_restaurant_id:=old.restaurant_id;a.old_branch_id:=old.branch_id;
 a.current_restaurant_id:=current_device.restaurant_id;a.current_branch_id:=current_device.branch_id;
 select m.id into a.old_membership_id from public.memberships m where m.app_user_id=actor and m.organization_id=old.organization_id
  and m.status='active' and m.deleted_at is null and app.role_rank(m.role)>=2
  and(m.restaurant_id is null or m.restaurant_id=old.restaurant_id) and(m.branch_id is null or m.branch_id=old.branch_id)
  order by app.role_rank(m.role) desc,m.id limit 1;
 select m.id into a.current_membership_id from public.memberships m where m.app_user_id=actor and m.organization_id=current_device.organization_id
  and m.status='active' and m.deleted_at is null and app.role_rank(m.role)>=2
  and(m.restaurant_id is null or m.restaurant_id=current_device.restaurant_id) and(m.branch_id is null or m.branch_id=current_device.branch_id)
  order by app.role_rank(m.role) desc,m.id limit 1;
 if not app.pos_alert_reconciliation_admin_valid(a) then return jsonb_build_object('ok',false,'error','permission_denied');end if;
 select * into pin from public.pin_sessions where id=p_current_pin_session_id and device_session_id=ds.id for share;
 if not found or pin.organization_id<>ds.organization_id or pin.restaurant_id<>ds.restaurant_id or pin.branch_id<>ds.branch_id
  or not pin.is_active or pin.ended_at is not null or pin.expires_at is null or pin.expires_at<=clock_timestamp() then
  return jsonb_build_object('ok',false,'error','invalid_session');end if;
 -- No credential is accepted by or enters this administrative intent/ledger.
 fp:=encode(sha256(convert_to(jsonb_build_object('old_registration',p_old_registration_id,'old_generation',p_expected_old_generation,
  'old_device',p_expected_old_device_id,'current_device',p_current_device_id,'current_session',p_expected_current_device_session_id,
  'current_pin',p_current_pin_session_id,'approved',p_approve_old_to_current)::text,'UTF8')),'hex');
 replay:=app.management_idem_check(actor,p_client_request_id,'approve_pos_alert_installation_reconciliation',fp);
 if replay is not null then return replay;end if;
 -- Device/pairing/session locks precede registration locks, including against
 -- ordinary non-alert core renewal/revocation writers outside our alert lock.
 if not app.pos_alert_old_owner_retired(old.device_id) then return jsonb_build_object('ok',false,'error','active_owner');end if;
 select * into old from app.pos_order_alert_registrations where id=p_old_registration_id for update;
 select * into owner from app.pos_order_alert_installation_owners where installation_id=old.installation_id for update;
 if not found or old.retired_at is not null or old.device_id<>p_expected_old_device_id or old.generation<>p_expected_old_generation
  or owner.device_id<>old.device_id or owner.organization_id<>old.organization_id
  or owner.restaurant_id<>old.restaurant_id or owner.branch_id<>old.branch_id then
  return jsonb_build_object('ok',false,'error','ownership_conflict');end if;
 if not app.pos_alert_reconciliation_admin_valid(a) then return jsonb_build_object('ok',false,'error','permission_denied');end if;
 v_now:=clock_timestamp();
 if exists(select 1 from app.pos_order_alert_reconciliation_approvals x where x.installation_id=old.installation_id
  and x.consumed_at is null and x.expires_at>v_now) then return jsonb_build_object('ok',false,'error','approval_pending');end if;
 a.id:=gen_random_uuid();a.client_request_id:=p_client_request_id;a.installation_id:=old.installation_id;
 a.old_registration_id:=old.id;a.expected_old_generation:=old.generation;a.old_device_id:=old.device_id;
 a.current_device_id:=p_current_device_id;a.current_device_session_id:=p_expected_current_device_session_id;
 a.current_pin_session_id:=p_current_pin_session_id;a.expected_ownership_version:=owner.ownership_version;
 a.created_at:=v_now;a.expires_at:=v_now+interval '5 minutes';
 result:=jsonb_build_object('ok',true,'approval_id',a.id,'expires_at',a.expires_at);
 replay:=app.management_claim_request(actor,p_client_request_id,'approve_pos_alert_installation_reconciliation',fp,result);
 if replay is not null then return replay;end if;
 insert into app.pos_order_alert_reconciliation_approvals select (a).*;
 perform app.management_audit(old.organization_id,old.restaurant_id,old.branch_id,'pos_alert.reconciliation.approved',null,
  jsonb_build_object('approval_id',a.id,'old_registration_id',old.id,'old_device_id',old.device_id,
   'current_device_id',a.current_device_id,'current_device_session_id',a.current_device_session_id,'expires_at',a.expires_at));
 return result;
exception when others or query_canceled then
 -- A caught failure rolls back this entire function's writes, including the
 -- request claim and audit. Never return SQLERRM, SQLSTATE detail or parameters.
 return jsonb_build_object('ok',false,'error','unavailable');
end; $$;
create function public.approve_pos_alert_installation_reconciliation(
 p_client_request_id uuid,p_old_registration_id uuid,p_expected_old_generation uuid,p_expected_old_device_id uuid,
 p_current_device_id uuid,p_current_pin_session_id uuid,
 p_expected_current_device_session_id uuid,p_approve_old_to_current boolean)
returns jsonb language sql volatile security invoker set search_path='' as $$
 select app.approve_pos_alert_installation_reconciliation(p_client_request_id,p_old_registration_id,p_expected_old_generation,
  p_expected_old_device_id,p_current_device_id,p_current_pin_session_id,
  p_expected_current_device_session_id,p_approve_old_to_current);
$$;
revoke all on function app.approve_pos_alert_installation_reconciliation(uuid,uuid,uuid,uuid,uuid,uuid,uuid,boolean),
 public.approve_pos_alert_installation_reconciliation(uuid,uuid,uuid,uuid,uuid,uuid,uuid,boolean) from public,anon,authenticated,service_role;
grant execute on function app.approve_pos_alert_installation_reconciliation(uuid,uuid,uuid,uuid,uuid,uuid,uuid,boolean),
 public.approve_pos_alert_installation_reconciliation(uuid,uuid,uuid,uuid,uuid,uuid,uuid,boolean) to authenticated;

create or replace function app.pos_register_order_alert(p_installation_id uuid,p_fcm_token text,p_status_secret text,
  p_device_id uuid,p_pin_session_id uuid,p_device_session_token text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_context jsonb; v_setting app.pos_order_alert_settings; v_registration app.pos_order_alert_registrations;
  v_now timestamptz; v_deadline timestamptz; v_hash text;
  v_attempt uuid; v_installation_valid boolean; v_secret_valid boolean;
  v_token_length_valid boolean; v_token_forbidden boolean; v_installation_conflict boolean; v_token_conflict boolean;
  v_owner app.pos_order_alert_installation_owners;v_old app.pos_order_alert_registrations;
  v_approval app.pos_order_alert_reconciliation_approvals;v_approval_count integer;
  v_admin_valid boolean:=false;v_transfer boolean:=false;v_secret_hash text;v_proof jsonb;
begin
  if not app.lock_pos_order_alert_writes() then return jsonb_build_object('ok',false,'error','unavailable');end if;
  begin
    v_attempt:=app.begin_pos_alert_registration_observation();
  exception when others then v_attempt:=null;
  end;
  -- The same guard order, with NULL for every predicate not reached. UUID syntax
  -- is enforced by the existing typed argument; its in-function guard is NULL.
  v_installation_valid:=p_installation_id is not null;
  if v_installation_valid then
    v_secret_valid:=p_status_secret is not null;
    if v_secret_valid then v_secret_valid:=p_status_secret ~ '^[0-9a-f]{64}$'; end if;
    if v_secret_valid then
      v_token_length_valid:=p_fcm_token is not null;
      if v_token_length_valid then
        v_token_length_valid:=length(p_fcm_token) between 20 and 4096;
      end if;
      if v_token_length_valid then v_token_forbidden:=p_fcm_token ~ '[[:space:][:cntrl:]]'; end if;
    end if;
  end if;
  if v_installation_valid is not true or v_secret_valid is not true
    or v_token_length_valid is not true or v_token_forbidden is distinct from false then
    begin
      perform app.record_pos_alert_registration_rejection(v_attempt,'INPUT_INVALID',
        v_installation_valid,v_secret_valid,v_token_length_valid,v_token_forbidden,null,null);
    exception when others then null;
    end;
    return jsonb_build_object('ok',false,'error','invalid_request'); end if;
  -- On the reconciliation path, take the already-approved human authority
  -- locks before POS context, matching app_user -> membership management order.
  -- This read does not authorize the caller; fresh POS proof still comes next.
  select * into v_owner from app.pos_order_alert_installation_owners where installation_id=p_installation_id;
  if found and v_owner.device_id<>p_device_id then
    select count(*) into v_approval_count from app.pos_order_alert_reconciliation_approvals a
      where a.installation_id=p_installation_id and a.current_device_id=p_device_id
        and a.current_pin_session_id=p_pin_session_id and a.consumed_at is null and a.expires_at>clock_timestamp();
    if v_approval_count=1 then
      select * into v_approval from app.pos_order_alert_reconciliation_approvals a
        where a.installation_id=p_installation_id and a.current_device_id=p_device_id
          and a.current_pin_session_id=p_pin_session_id and a.consumed_at is null and a.expires_at>clock_timestamp();
      -- Token-proven normal hierarchy comes before human person locks. This
      -- prevents a non-alert inbox context holding this device from waiting
      -- for our person lock while we wait for its device. Full PIN context is
      -- still checked immediately below; no context or core writer is changed.
      v_proof:=app.renew_device_session(p_device_id,p_device_session_token);
      if v_proof->>'ok'='true' and (v_proof->>'device_session_id')::uuid=v_approval.current_device_session_id
        and (v_proof->>'organization_id')::uuid=v_approval.organization_id
        and (v_proof->>'restaurant_id')::uuid=v_approval.current_restaurant_id
        and (v_proof->>'branch_id')::uuid=v_approval.current_branch_id then
        v_admin_valid:=app.pos_alert_reconciliation_admin_valid(v_approval);
      end if;
    end if;
  end if;
  v_context:=app.pos_web_order_context(p_pin_session_id,p_device_id,p_device_session_token);
  if v_context->>'ok' is distinct from 'true' then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  -- Entry correlation may be unavailable during an anonymous-principal rebind.
  -- Attach only after the UNCHANGED device/PIN context has actually authorized
  -- this scope; never repeat auth, or create a second observation for one call.
  if v_attempt is null then
    begin
      v_attempt:=app.begin_pos_alert_registration_observation(
        (v_context->>'organization_id')::uuid,(v_context->>'restaurant_id')::uuid,
        (v_context->>'branch_id')::uuid,p_device_id,(v_context->>'device_session_id')::uuid);
    exception when others then v_attempt:=null;
    end;
  end if;
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
  v_secret_hash:=encode(sha256(convert_to(p_status_secret,'UTF8')),'hex');
  select * into v_owner from app.pos_order_alert_installation_owners where installation_id=p_installation_id for update;
  v_installation_conflict:=found and (v_owner.device_id<>p_device_id
    or v_owner.organization_id<>(v_context->>'organization_id')::uuid
    or v_owner.restaurant_id<>(v_context->>'restaurant_id')::uuid
    or v_owner.branch_id<>(v_context->>'branch_id')::uuid);
  if v_installation_conflict and v_admin_valid and v_approval.id is not null then
    -- Retired ownership does not authenticate itself. Match the complete exact
    -- approval to a fresh context and compare the generation after every wait.
    select * into v_approval from app.pos_order_alert_reconciliation_approvals where id=v_approval.id for update;
    select * into v_old from app.pos_order_alert_registrations where id=v_approval.old_registration_id;
    v_transfer:=v_approval.consumed_at is null and v_approval.expires_at>clock_timestamp()
      and v_approval.installation_id=p_installation_id and v_old.installation_id=p_installation_id
      and v_old.retired_at is null and v_old.device_id=v_approval.old_device_id
      and v_old.generation=v_approval.expected_old_generation
      and v_owner.device_id=v_old.device_id and v_owner.ownership_version=v_approval.expected_ownership_version
      and v_owner.organization_id=v_old.organization_id and v_owner.restaurant_id=v_old.restaurant_id and v_owner.branch_id=v_old.branch_id
      and v_approval.current_device_id=p_device_id and v_approval.current_pin_session_id=p_pin_session_id
      and v_approval.current_device_session_id=(v_context->>'device_session_id')::uuid
      and v_approval.organization_id=v_old.organization_id and v_old.organization_id=(v_context->>'organization_id')::uuid
      and v_approval.old_restaurant_id=v_old.restaurant_id and v_approval.old_branch_id=v_old.branch_id
      and v_approval.current_restaurant_id=(v_context->>'restaurant_id')::uuid and v_approval.current_branch_id=(v_context->>'branch_id')::uuid;
    if v_transfer then
      -- Hold old-device retirement locks before its registration row lock.
      v_transfer:=app.pos_alert_old_owner_retired(v_old.device_id)
        and app.pos_alert_reconciliation_admin_valid(v_approval);
      select * into v_old from app.pos_order_alert_registrations where id=v_approval.old_registration_id for update;
      v_transfer:=v_transfer and found and v_old.retired_at is null and v_old.device_id=v_approval.old_device_id
        and v_old.installation_id=p_installation_id and v_old.generation=v_approval.expected_old_generation;
    end if;
    if v_transfer then v_installation_conflict:=false;end if;
  end if;
  if v_installation_conflict then
    begin
      perform app.record_pos_alert_registration_rejection(v_attempt,'INSTALLATION_CONFLICT',
        v_installation_valid,v_secret_valid,v_token_length_valid,v_token_forbidden,true,null,
        (v_context->>'organization_id')::uuid,(v_context->>'restaurant_id')::uuid,
        (v_context->>'branch_id')::uuid,p_device_id,(v_context->>'device_session_id')::uuid);
    exception when others then null;
    end;
    return jsonb_build_object('ok',false,'error','invalid_request'); end if;
  -- Token ownership is evaluated from THIS normal foreground call. Only the
  -- explicitly approved old registration may be retired; every unrelated
  -- enabled token owner still refuses before any ownership/approval mutation.
  select exists(select 1 from app.pos_order_alert_registrations r
    where r.enabled and r.token_hash=v_hash and r.device_id<>p_device_id
      and (not v_transfer or r.id<>v_old.id)) into v_token_conflict;
  if v_token_conflict then
    begin
      perform app.record_pos_alert_registration_rejection(v_attempt,'TOKEN_CONFLICT',
        v_installation_valid,v_secret_valid,v_token_length_valid,v_token_forbidden,false,true,
        (v_context->>'organization_id')::uuid,(v_context->>'restaurant_id')::uuid,
        (v_context->>'branch_id')::uuid,p_device_id,(v_context->>'device_session_id')::uuid);
    exception when others then null;
    end;
    return jsonb_build_object('ok',false,'error','invalid_request'); end if;
  if exists(select 1 from app.pos_order_alert_registrations r where r.installation_id=p_installation_id
      and (r.retired_at is not null or r.device_id<>p_device_id) and r.status_secret_hash=v_secret_hash) then
    -- Existing native v70 clears delegated authority after the rejected enable
    -- and produces a fresh secret on the next normal foreground preparation.
    -- Reusing a historical capability would let its former holder read/disable
    -- the new binding because those APIs intentionally do not take generation.
    return jsonb_build_object('ok',false,'error','invalid_request');
  end if;
  if v_deadline<=clock_timestamp() then return jsonb_build_object('ok',false,'error','invalid_session');end if;
  if v_transfer then
    update app.pos_order_alert_registrations set enabled=false,retired_at=clock_timestamp(),generation=gen_random_uuid()
      where id=v_old.id and retired_at is null and generation=v_approval.expected_old_generation;
    if not found then raise exception 'alert ownership changed' using errcode='40001';end if;
    update app.pos_order_alert_installation_owners set device_id=p_device_id,
      restaurant_id=(v_context->>'restaurant_id')::uuid,branch_id=(v_context->>'branch_id')::uuid,
      ownership_version=ownership_version+1,updated_at=clock_timestamp()
      where installation_id=p_installation_id and ownership_version=v_approval.expected_ownership_version;
    if not found then raise exception 'alert ownership changed' using errcode='40001';end if;
    -- Old lease identities remain historical. A send already issued outside
    -- this transaction cannot be undone; new native binding rejects old IDs.
    update app.pos_order_alert_deliveries set state='abandoned',lease_id=null,lease_until=null
      where registration_id=v_old.id and state in('queued','leased');
  elsif v_owner.installation_id is null then
    insert into app.pos_order_alert_installation_owners(installation_id,organization_id,restaurant_id,branch_id,device_id)
      values(p_installation_id,(v_context->>'organization_id')::uuid,(v_context->>'restaurant_id')::uuid,
        (v_context->>'branch_id')::uuid,p_device_id);
  end if;
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
  on conflict(installation_id) where retired_at is null do update set generation=gen_random_uuid(),
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
  if v_transfer then
    update app.pos_order_alert_reconciliation_approvals set consumed_at=clock_timestamp(),new_registration_id=v_registration.id
      where id=v_approval.id and consumed_at is null and expires_at>clock_timestamp();
    if not found then raise exception 'alert approval changed' using errcode='40001';end if;
    -- The anonymous POS transport is not the human approver. This actor was
    -- selected from the private approval, locked and revalidated above.
    insert into public.audit_events(organization_id,restaurant_id,branch_id,actor_app_user_id,device_id,action,reason,old_values,new_values)
      values(v_approval.organization_id,v_approval.current_restaurant_id,v_approval.current_branch_id,
        v_approval.approved_by_app_user_id,p_device_id,'pos_alert.reconciliation.consumed',null,
        jsonb_build_object('approval_id',v_approval.id,'registration_id',v_old.id,'device_id',v_old.device_id),
        jsonb_build_object('registration_id',v_registration.id,'device_id',p_device_id));
  end if;
  return jsonb_build_object('ok',true,'registration_id',v_registration.id,'generation',v_registration.generation,'authority_expires_at',v_deadline);
exception when others or query_canceled then
  -- The exception block rolls back every write in this invocation. No error
  -- detail, SQL statement, input, FCM token or delegated secret is emitted.
  return jsonb_build_object('ok',false,'error','unavailable');
end; $$;

-- Current-owner readers retain their existing public response contracts.
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
 where p_registration.retired_at is null
   and exists(select 1 from app.pos_order_alert_installation_owners own where own.installation_id=p_registration.installation_id
     and own.device_id=p_registration.device_id and own.organization_id=p_registration.organization_id
     and own.restaurant_id=p_registration.restaurant_id and own.branch_id=p_registration.branch_id)
   and p_registration.enabled and p_registration.authority_expires_at>statement_timestamp()
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

create or replace function app.pos_order_alert_status(p_installation_id uuid,p_status_secret_hash text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_registration app.pos_order_alert_registrations; v_deadline timestamptz; v_now timestamptz:=statement_timestamp(); v_rows jsonb;
begin
  if p_status_secret_hash is null or p_status_secret_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok',false,'error','unauthorized'); end if;
  select * into v_registration from app.pos_order_alert_registrations where retired_at is null and installation_id=p_installation_id
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

create or replace function app.pos_disable_order_alert(p_installation_id uuid,p_status_secret_hash text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
begin
  if not app.lock_pos_order_alert_writes() then return jsonb_build_object('ok',false,'error','unavailable');end if;
  if p_status_secret_hash is null or p_status_secret_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok',false,'error','unauthorized'); end if;
  update app.pos_order_alert_registrations set enabled=false where retired_at is null and installation_id=p_installation_id
    and status_secret_hash=p_status_secret_hash;
  if not found then return jsonb_build_object('ok',false,'error','unauthorized'); end if;
  return jsonb_build_object('ok',true);
end; $$;

create or replace function app.pos_refresh_order_alert_token(p_installation_id uuid,p_status_secret_hash text,p_fcm_token text,p_expected_generation uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_registration app.pos_order_alert_registrations; v_deadline timestamptz; v_hash text;
begin
  if not app.lock_pos_order_alert_writes() then return jsonb_build_object('ok',false,'error','unavailable');end if;
  if p_expected_generation is null or p_status_secret_hash is null or p_status_secret_hash !~ '^[0-9a-f]{64}$'
    or p_fcm_token is null or length(p_fcm_token) not between 20 and 4096 or p_fcm_token ~ '[[:space:][:cntrl:]]' then
    return jsonb_build_object('ok',false,'error','unauthorized'); end if;
  select * into v_registration from app.pos_order_alert_registrations where retired_at is null and installation_id=p_installation_id
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

create or replace function app.pos_claim_order_alert_deliveries(p_limit integer default 10)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_now timestamptz:=clock_timestamp(); v_rows jsonb; v_branches uuid[];
begin
  if not app.lock_pos_order_alert_writes() then return jsonb_build_object('ok',false,'error','unavailable');end if;
  v_now:=clock_timestamp();
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

create or replace function app.pos_finish_order_alert_delivery(p_delivery_id uuid,p_lease_id uuid,p_outcome text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_delivery app.pos_order_alert_deliveries;
begin
  if not app.lock_pos_order_alert_writes() then return jsonb_build_object('ok',false,'error','unavailable');end if;
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

-- Operator revision insertion participates in the same writer serialization.
-- This does not change the enabled setting, install a revision, or alter Cron.
create or replace function app.set_pos_order_alerts(p_enabled boolean,p_reason text,p_operator_reference text)
returns bigint language plpgsql security definer set search_path='' as $$
declare v_revision bigint;
begin
 if p_enabled is null then raise exception 'enabled required' using errcode='22023';end if;
 if not app.lock_pos_order_alert_writes() then raise exception 'alert operation unavailable' using errcode='55P03';end if;
 insert into app.pos_order_alert_settings(enabled,reason,operator_reference)
  values(p_enabled,p_reason,p_operator_reference) returning revision into v_revision;
 return v_revision;
end; $$;

-- New private objects have the same restricted owner regardless of which
-- privileged migration connection prepared the DDL. Existing ACLs stay intact.
alter table app.pos_order_alert_installation_owners owner to postgres;
alter table app.pos_order_alert_reconciliation_approvals owner to postgres;
alter function app.lock_pos_order_alert_writes() owner to postgres;
alter function app.pos_alert_reconciliation_admin_valid(app.pos_order_alert_reconciliation_approvals) owner to postgres;
alter function app.pos_alert_old_owner_retired(uuid) owner to postgres;
alter function app.approve_pos_alert_installation_reconciliation(uuid,uuid,uuid,uuid,uuid,uuid,uuid,boolean) owner to postgres;
alter function public.approve_pos_alert_installation_reconciliation(uuid,uuid,uuid,uuid,uuid,uuid,uuid,boolean) owner to postgres;

commit;
