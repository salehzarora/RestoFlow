-- BIZBOT-POS-ALERT-PRINT-NOTICE-001: forward correction of private capture
-- correlation only. No capture is armed, history erased or registration moved.
begin;

alter table app.pos_alert_registration_captures
  alter column auth_user_id drop not null,
  add column target_device_id uuid,
  add column target_device_session_id uuid,
  add constraint pos_alert_capture_anchor_shape check (
    (auth_user_id is not null and target_device_id is null and target_device_session_id is null)
    or (auth_user_id is null and target_device_id is not null and target_device_session_id is not null)
  ),
  add constraint pos_alert_capture_session unique (target_device_session_id);

-- Both entry and post-context attachment use this SAME complete candidate set.
-- The five optional-in-meaning arguments have no SQL defaults and are supplied
-- ONLY after the existing pos_web_order_context succeeds. The entry wrapper
-- passes five NULLs, never client-selected device/PIN/session identifiers.
create function app.begin_pos_alert_registration_observation(
  p_organization_id uuid,p_restaurant_id uuid,p_branch_id uuid,
  p_device_id uuid,p_device_session_id uuid)
returns uuid language plpgsql volatile set search_path='' set lock_timeout='25ms' as $$
declare v_captures uuid[]; v_attempt uuid; v_now timestamptz := clock_timestamp();
begin
  with active_captures as materialized (
    select c.* from app.pos_alert_registration_captures c
    where c.starts_at<=v_now and c.expires_at>v_now
  ), live_anchors as materialized (
    select c.id,ds.auth_user_id,ds.id as session_id,ds.device_id,
      ds.organization_id,ds.restaurant_id,ds.branch_id
    from active_captures c
    join public.device_sessions ds on ds.id=c.target_device_session_id
      and ds.device_id=c.target_device_id
    join public.devices d on d.id=ds.device_id and d.organization_id=ds.organization_id
      and d.restaurant_id=ds.restaurant_id and d.branch_id=ds.branch_id
    join public.device_pairings dp on dp.id=ds.device_pairing_id and dp.device_id=d.id
      and dp.organization_id=d.organization_id and dp.restaurant_id=d.restaurant_id and dp.branch_id=d.branch_id
    join public.organizations o on o.id=d.organization_id
    join public.restaurants r on r.id=d.restaurant_id and r.organization_id=o.id
    join public.branches b on b.id=d.branch_id and b.restaurant_id=r.id and b.organization_id=o.id
    where c.auth_user_id is null and ds.is_active and ds.revoked_at is null and ds.expires_at>v_now
      and d.device_type='pos' and d.is_active and d.deleted_at is null
      and dp.status='active' and dp.revoked_at is null and dp.deleted_at is null
      and o.status='active' and o.deleted_at is null and r.status='active' and r.deleted_at is null
      and b.status='active' and b.deleted_at is null
  )
  select array_agg(c.id) into v_captures from active_captures c where
    -- Legacy captures remain private and unchanged, including closed evidence.
    (c.auth_user_id=auth.uid() and c.target_device_id is null)
    or exists(select 1 from live_anchors a where a.id=c.id and (
      -- Pre-auth correlation uses ONLY a trusted server binding. A principal
      -- shared with any other historical/live device is deliberately ambiguous.
      (a.auth_user_id=auth.uid()
        and (select count(distinct s.device_id) from public.device_sessions s
          where s.auth_user_id=a.auth_user_id)=1
        and (select count(*) from public.device_sessions s where s.device_id=a.device_id
          and s.is_active and s.revoked_at is null and s.expires_at>v_now)=1)
      -- This alternative is reachable ONLY from the authorized-context call.
      or (a.organization_id=p_organization_id and a.restaurant_id=p_restaurant_id
        and a.branch_id=p_branch_id and a.device_id=p_device_id and a.session_id=p_device_session_id)
    ));
  -- Never choose one of multiple candidates, including legacy + anchored rows.
  if coalesce(cardinality(v_captures),0)<>1 then return null; end if;
  v_attempt:=gen_random_uuid();
  insert into app.pos_alert_registration_observations(attempt_id,capture_id,observed_at)
    values(v_attempt,v_captures[1],v_now);
  return v_attempt;
exception when others then
  -- No exception/statement/parameter logging. Missing evidence remains UNKNOWN.
  return null;
end; $$;
alter function app.begin_pos_alert_registration_observation(uuid,uuid,uuid,uuid,uuid) owner to postgres;
revoke all on function app.begin_pos_alert_registration_observation(uuid,uuid,uuid,uuid,uuid)
  from public,anon,authenticated,service_role;

create or replace function app.begin_pos_alert_registration_observation()
returns uuid language plpgsql volatile set search_path='' set lock_timeout='25ms' as $$
begin
  return app.begin_pos_alert_registration_observation(null,null,null,null,null);
exception when others then return null;
end; $$;

-- A principal binding is a correlation hint, not registration authority. If
-- the existing POS context proves a DIFFERENT device/session, do not stamp its
-- refusal into this anchor. Leave the entry unclassified/UNKNOWN; never move it
-- to another capture or produce a second row. Legacy behavior is unchanged.
create or replace function app.record_pos_alert_registration_rejection(
  p_attempt uuid,p_classification text,p_installation_valid boolean,
  p_secret_valid boolean,p_token_length_valid boolean,p_token_forbidden boolean,
  p_installation_conflict boolean,p_token_conflict boolean,
  p_organization_id uuid default null,p_restaurant_id uuid default null,
  p_branch_id uuid default null,p_device_id uuid default null,
  p_device_session_id uuid default null)
returns void language plpgsql volatile set search_path='' set lock_timeout='25ms' as $$
begin
  if p_attempt is null then return; end if;
  update app.pos_alert_registration_observations o set
    classification=p_classification,
    installation_id_present_and_valid=p_installation_valid,
    status_secret_format_valid=p_secret_valid,
    fcm_token_length_valid=p_token_length_valid,
    fcm_token_has_forbidden_characters=p_token_forbidden,
    installation_conflict=p_installation_conflict,
    enabled_token_conflict=p_token_conflict,
    organization_id=p_organization_id,restaurant_id=p_restaurant_id,
    branch_id=p_branch_id,device_id=p_device_id,device_session_id=p_device_session_id
  where o.attempt_id=p_attempt and o.classification is null
    and (p_classification='INPUT_INVALID' or exists(
      select 1 from app.pos_alert_registration_captures c where c.id=o.capture_id
        and (c.target_device_id is null or
          (c.target_device_id=p_device_id and c.target_device_session_id=p_device_session_id))
    ));
exception when others then return;
end; $$;

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
