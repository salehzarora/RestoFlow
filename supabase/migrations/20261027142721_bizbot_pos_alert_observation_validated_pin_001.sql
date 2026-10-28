-- BIZBOT-POS-ALERT-OWNERSHIP-RECONCILIATION-001: private invocation reference.
-- Forward-only after 20261027004637, 20261027011255 and 20261027100332.
-- Owner-approved LOCAL preparation only; production application is separate.
-- No capture, reconciliation approval, registration or ownership write occurs.
begin;

alter table app.pos_alert_registration_observations
 add column validated_pin_session_id uuid,
 add constraint pos_alert_validated_pin_shape check ((
  validated_pin_session_id is null or (
   classification in ('INSTALLATION_CONFLICT','TOKEN_CONFLICT')
   and organization_id is not null and restaurant_id is not null
   and branch_id is not null and device_id is not null
   and device_session_id is not null
  )
 ) is true);
-- Inherit the existing private table owner, ACL and FORCE RLS unchanged.
-- Deliberately no FK: historical diagnostic evidence must not prevent ordinary
-- PIN-session retention/cleanup. This UUID is evidence of this invocation only,
-- never a credential or proof that a PIN session remains usable later.
comment on column app.pos_alert_registration_observations.validated_pin_session_id is
 'Private opaque reference to the actual PIN session validated by this rejection invocation; not current authority. No backfill; absent evidence remains UNKNOWN.';

create function app.record_pos_alert_validated_pin(
 p_attempt uuid,p_pin_session_id uuid,p_organization_id uuid,
 p_restaurant_id uuid,p_branch_id uuid,p_device_id uuid,
 p_device_session_id uuid,p_employee_profile_id uuid)
returns void language plpgsql volatile security invoker
 set search_path='' set lock_timeout='25ms' as $$
begin
 if p_attempt is null or p_pin_session_id is null or p_organization_id is null
  or p_restaurant_id is null or p_branch_id is null or p_device_id is null
  or p_device_session_id is null or p_employee_profile_id is null then return;end if;
 -- The registration hook passes its actual p_pin_session_id unchanged, only
 -- AFTER the same pos_web_order_context call has authorized it. That context
 -- holds the selected PIN row FOR SHARE until transaction end. Never choose a
 -- candidate by employee, activity, label, expiry ordering or latest timestamp.
 update app.pos_alert_registration_observations o
  set validated_pin_session_id=p_pin_session_id
  where o.attempt_id=p_attempt and o.validated_pin_session_id is null
   and o.classification in ('INSTALLATION_CONFLICT','TOKEN_CONFLICT')
   and o.organization_id=p_organization_id and o.restaurant_id=p_restaurant_id
   and o.branch_id=p_branch_id and o.device_id=p_device_id
   and o.device_session_id=p_device_session_id
   and exists(select 1 from app.pos_alert_registration_captures c
    where c.id=o.capture_id and (c.target_device_id is null or
     (c.target_device_id=p_device_id and c.target_device_session_id=p_device_session_id)))
   and exists(select 1 from public.pin_sessions ps
    where ps.id=p_pin_session_id and ps.device_session_id=p_device_session_id
     and ps.organization_id=p_organization_id and ps.restaurant_id=p_restaurant_id
     and ps.branch_id=p_branch_id and ps.employee_profile_id=p_employee_profile_id
     and ps.is_active and ps.ended_at is null and ps.expires_at>clock_timestamp());
exception when others or query_canceled then
 -- Diagnostic failure leaves the established business result/classification
 -- unchanged and the PIN reference UNKNOWN. Never emit SQLERRM or arguments.
 return;
end; $$;
alter function app.record_pos_alert_validated_pin(uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid) owner to postgres;
revoke all on function app.record_pos_alert_validated_pin(uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid)
 from public,anon,authenticated,service_role;

-- Patch only the two reviewed, post-context refusal hooks. Keep every input,
-- authentication, ownership, token and success-path statement byte-identical.
do $patch$
declare v_source text;v_definition text;v_replacement text;v_old text;v_new text;
 v_proc pg_catalog.pg_proc;
begin
 select p.* into v_proc from pg_catalog.pg_proc p
  where p.oid='app.pos_register_order_alert(uuid,text,text,uuid,uuid,text)'::regprocedure;
 v_source:=v_proc.prosrc;v_definition:=pg_get_functiondef(v_proc.oid);
 if encode(sha256(convert_to(v_source,'UTF8')),'hex')<>'917c6447a2f3de83aac83d404f3945850ddce69b1d5d8796ec615738f8c90d3f'
  or v_proc.proowner<>'postgres'::regrole or not v_proc.prosecdef
  or v_proc.provolatile<>'v' or v_proc.proisstrict or v_proc.proleakproof
  or v_proc.proparallel<>'u' or v_proc.proconfig is distinct from array['search_path=""']::text[]
  or v_proc.prorettype<>'jsonb'::regtype
  or v_proc.prolang<>(select oid from pg_catalog.pg_language where lanname='plpgsql')
  or v_proc.proacl is distinct from '{postgres=X/postgres,authenticated=X/postgres}'::aclitem[] then
  raise exception 'reviewed alert validated-PIN baseline differs' using errcode='55000';
 end if;
 v_replacement:=v_source;
 v_old:=$old_install$      perform app.record_pos_alert_conflicting_registration(v_attempt,v_conflicting_registration_id,
        (v_context->>'organization_id')::uuid,(v_context->>'restaurant_id')::uuid,
        (v_context->>'branch_id')::uuid,p_device_id,(v_context->>'device_session_id')::uuid);
    exception when others or query_canceled then null;
    end;
    return jsonb_build_object('ok',false,'error','invalid_request'); end if;$old_install$;
 v_new:=$new_install$      perform app.record_pos_alert_conflicting_registration(v_attempt,v_conflicting_registration_id,
        (v_context->>'organization_id')::uuid,(v_context->>'restaurant_id')::uuid,
        (v_context->>'branch_id')::uuid,p_device_id,(v_context->>'device_session_id')::uuid);
    exception when others or query_canceled then null;
    end;
    begin
      perform app.record_pos_alert_validated_pin(v_attempt,p_pin_session_id,
        (v_context->>'organization_id')::uuid,(v_context->>'restaurant_id')::uuid,
        (v_context->>'branch_id')::uuid,p_device_id,(v_context->>'device_session_id')::uuid,
        (v_context->>'employee_profile_id')::uuid);
    exception when others or query_canceled then null;
    end;
    return jsonb_build_object('ok',false,'error','invalid_request'); end if;$new_install$;
 if length(v_replacement)-length(replace(v_replacement,v_old,''))<>length(v_old) then
  raise exception 'reviewed installation rejection hook differs' using errcode='55000';
 end if;
 v_replacement:=replace(v_replacement,v_old,v_new);
 v_old:=$old_token$      perform app.record_pos_alert_registration_rejection(v_attempt,'TOKEN_CONFLICT',
        v_installation_valid,v_secret_valid,v_token_length_valid,v_token_forbidden,false,true,
        (v_context->>'organization_id')::uuid,(v_context->>'restaurant_id')::uuid,
        (v_context->>'branch_id')::uuid,p_device_id,(v_context->>'device_session_id')::uuid);
    exception when others then null;
    end;
    return jsonb_build_object('ok',false,'error','invalid_request'); end if;$old_token$;
 v_new:=$new_token$      perform app.record_pos_alert_registration_rejection(v_attempt,'TOKEN_CONFLICT',
        v_installation_valid,v_secret_valid,v_token_length_valid,v_token_forbidden,false,true,
        (v_context->>'organization_id')::uuid,(v_context->>'restaurant_id')::uuid,
        (v_context->>'branch_id')::uuid,p_device_id,(v_context->>'device_session_id')::uuid);
    exception when others then null;
    end;
    begin
      perform app.record_pos_alert_validated_pin(v_attempt,p_pin_session_id,
        (v_context->>'organization_id')::uuid,(v_context->>'restaurant_id')::uuid,
        (v_context->>'branch_id')::uuid,p_device_id,(v_context->>'device_session_id')::uuid,
        (v_context->>'employee_profile_id')::uuid);
    exception when others or query_canceled then null;
    end;
    return jsonb_build_object('ok',false,'error','invalid_request'); end if;$new_token$;
 if length(v_replacement)-length(replace(v_replacement,v_old,''))<>length(v_old) then
  raise exception 'reviewed token rejection hook differs' using errcode='55000';
 end if;
 v_replacement:=replace(v_replacement,v_old,v_new);
 if length(v_definition)-length(replace(v_definition,v_source,''))<>length(v_source) then
  raise exception 'reviewed alert definition differs' using errcode='55000';
 end if;
 execute replace(v_definition,v_source,v_replacement);
end;
$patch$;

commit;
