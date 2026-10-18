-- BIZBOT-HOME-ALERT-ALLOWLIST-RETARGET-001 — PREPARED / NOT APPLIED.
-- Exclusive notification-only HOME replacement. Printing remains on old hg.
-- Later application additionally requires verified Edge/Vercel OFF state;
-- SQL cannot establish those external settings or physical device identity.
begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- Preserve the registration settings -> registrations lock order. SHARE fences
-- operator INSERTs; ACCESS EXCLUSIVE fences registration writes and the CHECK.
-- No device/session/auth/order/printing table is locked or mutated here.
lock table app.pos_order_alert_settings in share mode;
lock table app.pos_order_alert_registrations in access exclusive mode;

do $retarget$
declare
  v_function pg_catalog.pg_proc;
  v_constraint pg_catalog.pg_constraint;
begin
  if coalesce((select enabled from app.pos_order_alert_settings
      order by revision desc limit 1), false) then
    raise exception 'notification retarget requires operator OFF' using errcode = '55000';
  end if;
  -- Any retained registration or delivery needs separate reconciliation, even
  -- if disabled/expired. Never delete or rewrite evidence to pass this gate.
  if exists(select 1 from app.pos_order_alert_registrations)
    or exists(select 1 from app.pos_order_alert_deliveries) then
    raise exception 'notification retarget requires clean registration/delivery baseline'
      using errcode = '55000';
  end if;

  select * into strict v_function from pg_catalog.pg_proc
    where oid = 'app.pos_register_order_alert(uuid,text,text,uuid,uuid,text)'::regprocedure;
  if md5(replace(v_function.prosrc, E'\r\n', E'\n')) <> '5d555962420420e06c25d1fb2791404e'
    or v_function.proowner <> 'postgres'::regrole or not v_function.prosecdef
    or v_function.provolatile <> 'v' or v_function.proconfig is distinct from array['search_path=""']
    or not has_function_privilege('authenticated', v_function.oid, 'EXECUTE')
    or has_function_privilege('anon', v_function.oid, 'EXECUTE')
    or has_function_privilege('service_role', v_function.oid, 'EXECUTE') then
    raise exception 'notification registration contract drift' using errcode = '55000';
  end if;
  select * into strict v_constraint from pg_catalog.pg_constraint
    where conrelid = 'app.pos_order_alert_registrations'::regclass
      and conname = 'pos_order_alert_registrations_check';
  if v_constraint.contype <> 'c' or not v_constraint.convalidated
    or pg_get_constraintdef(v_constraint.oid) <>
      $check$CHECK (((organization_id = '20605c2b-3145-4803-a990-bbec3d9c1096'::uuid) AND (restaurant_id = 'de3bbc64-edad-4ff4-bccd-c2ef217c1d56'::uuid) AND (branch_id = '2847c0be-3e31-45a5-957c-508729f1971e'::uuid) AND (device_id = 'bb80c0d8-6893-4e24-8eea-5a14cf545ecd'::uuid)))$check$ then
    raise exception 'notification registration scope constraint drift' using errcode = '55000';
  end if;
  if not exists(select 1 from pg_catalog.pg_class
      where oid = 'app.pos_order_alert_registrations'::regclass
        and relrowsecurity and relforcerowsecurity) then
    raise exception 'notification registration RLS drift' using errcode = '55000';
  end if;
end;
$retarget$;

-- Validated immediately under the same transaction/lock; no committed period
-- accepts both UUIDs and no NOT VALID constraint or compatibility fallback.
alter table app.pos_order_alert_registrations
  drop constraint pos_order_alert_registrations_check;
alter table app.pos_order_alert_registrations
  add constraint pos_order_alert_registrations_check check(
    organization_id = '20605c2b-3145-4803-a990-bbec3d9c1096'::uuid
    and restaurant_id = 'de3bbc64-edad-4ff4-bccd-c2ef217c1d56'::uuid
    and branch_id = '2847c0be-3e31-45a5-957c-508729f1971e'::uuid
    and device_id = 'd9f876fb-57e8-44ee-be94-f2284c6fc905'::uuid);

-- CREATE OR REPLACE preserves the existing owner and ACL. Signature, security,
-- search_path and entire body are unchanged except the one notification UUID.

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
  if p_device_id<>'d9f876fb-57e8-44ee-be94-f2284c6fc905'::uuid
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

commit;
