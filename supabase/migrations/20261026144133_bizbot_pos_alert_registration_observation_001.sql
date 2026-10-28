-- BIZBOT-POS-ALERT-PRINT-NOTICE-001: temporary, operator-armed observation.
-- No active capture is installed. No raw registration input, hash, exception,
-- conflicting identity, public RPC or public response field is added.
begin;

create table app.pos_alert_registration_captures (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null,
  starts_at timestamptz not null,
  expires_at timestamptz not null,
  constraint pos_alert_capture_window check (
    isfinite(starts_at) and isfinite(expires_at)
    and expires_at > starts_at and expires_at <= starts_at + interval '10 minutes'
  ),
  -- One operator-created window per principal; never changed by registration.
  constraint pos_alert_capture_principal unique (auth_user_id)
);
create table app.pos_alert_registration_observations (
  attempt_id uuid primary key,
  capture_id uuid not null,
  observed_at timestamptz not null,
  classification text check (classification in
    ('INPUT_INVALID','INSTALLATION_CONFLICT','TOKEN_CONFLICT')),
  installation_id_present_and_valid boolean,
  status_secret_format_valid boolean,
  fcm_token_length_valid boolean,
  fcm_token_has_forbidden_characters boolean,
  installation_conflict boolean,
  enabled_token_conflict boolean,
  -- Populated only AFTER the existing POS context authorizes these values.
  organization_id uuid,
  restaurant_id uuid,
  branch_id uuid,
  device_id uuid,
  device_session_id uuid,
  constraint pos_alert_observation_shape check ((
    (classification is null
      and installation_id_present_and_valid is null
      and status_secret_format_valid is null and fcm_token_length_valid is null
      and fcm_token_has_forbidden_characters is null
      and installation_conflict is null and enabled_token_conflict is null
      and organization_id is null and restaurant_id is null and branch_id is null
      and device_id is null and device_session_id is null)
    or (classification = 'INPUT_INVALID'
      and ((installation_id_present_and_valid is false
          and status_secret_format_valid is null and fcm_token_length_valid is null
          and fcm_token_has_forbidden_characters is null)
        or (installation_id_present_and_valid is true
          and status_secret_format_valid is false and fcm_token_length_valid is null
          and fcm_token_has_forbidden_characters is null)
        or (installation_id_present_and_valid is true
          and status_secret_format_valid is true and fcm_token_length_valid is false
          and fcm_token_has_forbidden_characters is null)
        or (installation_id_present_and_valid is true
          and status_secret_format_valid is true and fcm_token_length_valid is true
          and fcm_token_has_forbidden_characters is true))
      and installation_conflict is null and enabled_token_conflict is null
      and organization_id is null and restaurant_id is null and branch_id is null
      and device_id is null and device_session_id is null)
    or (classification in ('INSTALLATION_CONFLICT','TOKEN_CONFLICT')
      and installation_id_present_and_valid is true
      and status_secret_format_valid is true and fcm_token_length_valid is true
      and fcm_token_has_forbidden_characters is false
      and ((classification = 'INSTALLATION_CONFLICT'
        and installation_conflict is true and enabled_token_conflict is null)
        or (classification = 'TOKEN_CONFLICT'
          and installation_conflict is false and enabled_token_conflict is true))
      and organization_id is not null and restaurant_id is not null
      and branch_id is not null and device_id is not null
      and device_session_id is not null)
  ) is true)
);
create index pos_alert_observation_capture on
  app.pos_alert_registration_observations(capture_id);
-- Match the established registration SECURITY DEFINER owner, including when
-- the migration runner is supabase_admin rather than postgres.
alter table app.pos_alert_registration_captures owner to postgres;
alter table app.pos_alert_registration_observations owner to postgres;
alter table app.pos_alert_registration_captures enable row level security;
alter table app.pos_alert_registration_captures force row level security;
alter table app.pos_alert_registration_observations enable row level security;
alter table app.pos_alert_registration_observations force row level security;
revoke all on app.pos_alert_registration_captures,
  app.pos_alert_registration_observations from public,anon,authenticated,service_role;

-- Only called by the existing SECURITY DEFINER registration. Auth.uid() is the
-- gateway-validated principal, NOT proof of a caller-supplied device identity.
-- Append one row per invocation, including success/other early returns: never
-- lock a shared capture row and silently skip a concurrent invocation.
create function app.begin_pos_alert_registration_observation()
returns uuid language plpgsql volatile set search_path='' set lock_timeout='25ms' as $$
declare v_capture uuid; v_attempt uuid; v_now timestamptz := clock_timestamp();
begin
  select id into v_capture from app.pos_alert_registration_captures
    where auth_user_id=auth.uid() and starts_at<=v_now and expires_at>v_now;
  if not found then return null; end if;
  v_attempt:=gen_random_uuid();
  insert into app.pos_alert_registration_observations(attempt_id,capture_id,observed_at)
    values(v_attempt,v_capture,v_now);
  return v_attempt;
exception when others then
  -- Deliberately no SQLERRM/DETAIL/CONTEXT or server log. A missing record is
  -- UNKNOWN, never evidence that a predicate was false or no call occurred.
  return null;
end; $$;
alter function app.begin_pos_alert_registration_observation() owner to postgres;
revoke all on function app.begin_pos_alert_registration_observation()
  from public,anon,authenticated,service_role;

-- Typed, allowlisted arguments only: no input text, token/hash, installation,
-- PIN, conflicting row or exception can enter the diagnostic sink.
create function app.record_pos_alert_registration_rejection(
  p_attempt uuid,p_classification text,p_installation_valid boolean,
  p_secret_valid boolean,p_token_length_valid boolean,p_token_forbidden boolean,
  p_installation_conflict boolean,p_token_conflict boolean,
  p_organization_id uuid default null,p_restaurant_id uuid default null,
  p_branch_id uuid default null,p_device_id uuid default null,
  p_device_session_id uuid default null)
returns void language plpgsql volatile set search_path='' set lock_timeout='25ms' as $$
begin
  if p_attempt is null then return; end if;
  update app.pos_alert_registration_observations set
    classification=p_classification,
    installation_id_present_and_valid=p_installation_valid,
    status_secret_format_valid=p_secret_valid,
    fcm_token_length_valid=p_token_length_valid,
    fcm_token_has_forbidden_characters=p_token_forbidden,
    installation_conflict=p_installation_conflict,
    enabled_token_conflict=p_token_conflict,
    organization_id=p_organization_id,restaurant_id=p_restaurant_id,
    branch_id=p_branch_id,device_id=p_device_id,device_session_id=p_device_session_id
  where attempt_id=p_attempt and classification is null;
exception when others then
  -- Diagnostic failure must not replace the established registration response.
  return;
end; $$;
alter function app.record_pos_alert_registration_rejection(
  uuid,text,boolean,boolean,boolean,boolean,boolean,boolean,uuid,uuid,uuid,uuid,uuid)
  owner to postgres;
revoke all on function app.record_pos_alert_registration_rejection(
  uuid,text,boolean,boolean,boolean,boolean,boolean,boolean,uuid,uuid,uuid,uuid,uuid)
  from public,anon,authenticated,service_role;

create or replace function app.pos_register_order_alert(p_installation_id uuid,p_fcm_token text,p_status_secret text,
  p_device_id uuid,p_pin_session_id uuid,p_device_session_token text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_context jsonb; v_setting app.pos_order_alert_settings; v_registration app.pos_order_alert_registrations;
  v_now timestamptz; v_deadline timestamptz; v_hash text;
  v_attempt uuid; v_installation_valid boolean; v_secret_valid boolean;
  v_token_length_valid boolean; v_token_forbidden boolean; v_installation_conflict boolean; v_token_conflict boolean;
begin
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
  -- A single statement snapshot, as in the original OR. MATERIALIZED evaluates
  -- the installation predicate once; CASE leaves the token predicate unchecked
  -- when it short-circuits. Neither result is reconstructed after rejection.
  with installation as materialized (
    select exists(select 1 from app.pos_order_alert_registrations
      where installation_id=p_installation_id and device_id<>p_device_id) as conflict
  )
  select conflict,case when conflict then null else
    exists(select 1 from app.pos_order_alert_registrations
      where enabled and token_hash=v_hash and device_id<>p_device_id) end
    into v_installation_conflict,v_token_conflict from installation;
  if v_installation_conflict then
    begin
      perform app.record_pos_alert_registration_rejection(v_attempt,'INSTALLATION_CONFLICT',
        v_installation_valid,v_secret_valid,v_token_length_valid,v_token_forbidden,true,null,
        (v_context->>'organization_id')::uuid,(v_context->>'restaurant_id')::uuid,
        (v_context->>'branch_id')::uuid,p_device_id,(v_context->>'device_session_id')::uuid);
    exception when others then null;
    end;
    return jsonb_build_object('ok',false,'error','invalid_request'); end if;
  if v_token_conflict then
    begin
      perform app.record_pos_alert_registration_rejection(v_attempt,'TOKEN_CONFLICT',
        v_installation_valid,v_secret_valid,v_token_length_valid,v_token_forbidden,false,true,
        (v_context->>'organization_id')::uuid,(v_context->>'restaurant_id')::uuid,
        (v_context->>'branch_id')::uuid,p_device_id,(v_context->>'device_session_id')::uuid);
    exception when others then null;
    end;
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

commit;
