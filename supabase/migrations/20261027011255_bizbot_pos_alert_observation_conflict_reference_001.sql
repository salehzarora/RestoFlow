-- BIZBOT-POS-ALERT-OWNERSHIP-RECONCILIATION-001: private diagnostic extension.
-- Forward-only dependency on the reviewed ownership-reconciliation definition.
-- No historical migration, ownership binding, authority or public response is
-- changed. No capture is armed and no registration is invoked by this DDL.
begin;

alter table app.pos_alert_registration_observations
 add column conflicting_registration_id uuid references app.pos_order_alert_registrations(id),
 add constraint pos_alert_conflicting_registration_shape check (
  conflicting_registration_id is null or (
   classification='INSTALLATION_CONFLICT' and installation_conflict is true
   and enabled_token_conflict is null
   and organization_id is not null and restaurant_id is not null and branch_id is not null
   and device_id is not null and device_session_id is not null
  ) is true
 );
-- Existing table owner, private ACL and FORCE RLS are inherited unchanged.

-- The caller supplies only the already captured, nullable row reference from
-- the authoritative ownership-decision statement. This hook never searches
-- registrations later or reconstructs an identity from labels/timestamps.
-- It cannot classify an attempt, supply missing authorization, or overwrite
-- an earlier reference. The existing 13-argument rejection-writer ABI stays
-- unchanged, including its default arguments.
create function app.record_pos_alert_conflicting_registration(
 p_attempt uuid,p_conflicting_registration_id uuid,p_organization_id uuid,
 p_restaurant_id uuid,p_branch_id uuid,p_device_id uuid,p_device_session_id uuid)
returns void language plpgsql volatile security invoker set search_path='' set lock_timeout='25ms' as $$
begin
 if p_attempt is null or p_conflicting_registration_id is null
  or p_organization_id is null or p_restaurant_id is null or p_branch_id is null
  or p_device_id is null or p_device_session_id is null then return;end if;
 update app.pos_alert_registration_observations o set conflicting_registration_id=p_conflicting_registration_id
  where o.attempt_id=p_attempt and o.conflicting_registration_id is null
   and o.classification='INSTALLATION_CONFLICT' and o.installation_conflict is true and o.enabled_token_conflict is null
   and o.organization_id=p_organization_id and o.restaurant_id=p_restaurant_id and o.branch_id=p_branch_id
   and o.device_id=p_device_id and o.device_session_id=p_device_session_id
   and exists(select 1 from app.pos_alert_registration_captures c where c.id=o.capture_id
    and (c.target_device_id is null or (c.target_device_id=p_device_id and c.target_device_session_id=p_device_session_id)));
exception when others or query_canceled then
 -- Failure of the FK, a locked/missing sink or any diagnostic fault leaves the
 -- established business classification intact and the reference UNKNOWN/NULL.
 return;
end; $$;
alter function app.record_pos_alert_conflicting_registration(uuid,uuid,uuid,uuid,uuid,uuid,uuid) owner to postgres;
revoke all on function app.record_pos_alert_conflicting_registration(uuid,uuid,uuid,uuid,uuid,uuid,uuid)
 from public,anon,authenticated,service_role;

-- Guard the exact reviewed function body and properties. Apply three precise
-- diagnostic edits to its existing definition, rather than replacing it with a
-- copied older registration implementation. All other bytes remain unchanged.
do $patch$
declare v_source text;v_definition text;v_replacement text;v_proc pg_catalog.pg_proc;
begin
 select p.* into v_proc
  from pg_catalog.pg_proc p where p.oid='app.pos_register_order_alert(uuid,text,text,uuid,uuid,text)'::regprocedure;
 v_definition:=pg_get_functiondef(v_proc.oid);
 v_source:=v_proc.prosrc;
 if encode(sha256(convert_to(v_source,'UTF8')),'hex')<>'3768044c00dfde3410490d7e21262ffdc8a137793dc2cc3454537f8b3f609994'
  or v_proc.proowner<>'postgres'::regrole or not v_proc.prosecdef or v_proc.provolatile<>'v'
  or v_proc.proisstrict or v_proc.proleakproof or v_proc.proparallel<>'u'
  or v_proc.proconfig is distinct from array['search_path=""']::text[]
  or v_proc.prorettype<>'jsonb'::regtype or v_proc.prolang<>(select oid from pg_catalog.pg_language where lanname='plpgsql') then
  raise exception 'reviewed alert registration baseline differs' using errcode='55000';
 end if;
 v_replacement:=v_source;
 if length(v_replacement)-length(replace(v_replacement,$old_declaration$  v_admin_valid boolean:=false;v_transfer boolean:=false;v_secret_hash text;v_proof jsonb;$old_declaration$,''))<>length($old_declaration$  v_admin_valid boolean:=false;v_transfer boolean:=false;v_secret_hash text;v_proof jsonb;$old_declaration$) then
  raise exception 'reviewed alert diagnostic patch differs' using errcode='55000';
 end if;
 v_replacement:=replace(v_replacement,$old_declaration$  v_admin_valid boolean:=false;v_transfer boolean:=false;v_secret_hash text;v_proof jsonb;$old_declaration$,$new_declaration$  v_admin_valid boolean:=false;v_transfer boolean:=false;v_secret_hash text;v_proof jsonb;
  v_ownership_decision record;v_conflicting_registration_id uuid;v_observation_lock_timeout text;$new_declaration$);

 if length(v_replacement)-length(replace(v_replacement,$old_decision$  select * into v_owner from app.pos_order_alert_installation_owners where installation_id=p_installation_id for update;
  v_installation_conflict:=found and (v_owner.device_id<>p_device_id
    or v_owner.organization_id<>(v_context->>'organization_id')::uuid
    or v_owner.restaurant_id<>(v_context->>'restaurant_id')::uuid
    or v_owner.branch_id<>(v_context->>'branch_id')::uuid);$old_decision$,''))<>length($old_decision$  select * into v_owner from app.pos_order_alert_installation_owners where installation_id=p_installation_id for update;
  v_installation_conflict:=found and (v_owner.device_id<>p_device_id
    or v_owner.organization_id<>(v_context->>'organization_id')::uuid
    or v_owner.restaurant_id<>(v_context->>'restaurant_id')::uuid
    or v_owner.branch_id<>(v_context->>'branch_id')::uuid);$old_decision$) then
  raise exception 'reviewed alert diagnostic patch differs' using errcode='55000';
 end if;
 v_replacement:=replace(v_replacement,$old_decision$  select * into v_owner from app.pos_order_alert_installation_owners where installation_id=p_installation_id for update;
  v_installation_conflict:=found and (v_owner.device_id<>p_device_id
    or v_owner.organization_id<>(v_context->>'organization_id')::uuid
    or v_owner.restaurant_id<>(v_context->>'restaurant_id')::uuid
    or v_owner.branch_id<>(v_context->>'branch_id')::uuid);$old_decision$,$new_decision$  -- The owner and ALL current installation rows are observed in one statement
  -- snapshot. A reference is recorded only for one exact non-retired row whose
  -- device and complete scope match the authoritative owner. Ambiguity never
  -- selects the convenient matching row and historical retired rows are ignored.
  v_observation_lock_timeout:=current_setting('lock_timeout');
  begin
    perform set_config('lock_timeout','25ms',true);
    select own as owner_row,
      (own.device_id<>p_device_id
        or own.organization_id<>(v_context->>'organization_id')::uuid
        or own.restaurant_id<>(v_context->>'restaurant_id')::uuid
        or own.branch_id<>(v_context->>'branch_id')::uuid) as installation_conflict,
      current_binding.conflicting_registration_id
      into v_ownership_decision
      from app.pos_order_alert_installation_owners own
      left join lateral (
        select case when count(*)=1 and bool_and(r.device_id=own.device_id
          and r.organization_id=own.organization_id and r.restaurant_id=own.restaurant_id and r.branch_id=own.branch_id)
          then (array_agg(r.id))[1] else null::uuid end as conflicting_registration_id
        from app.pos_order_alert_registrations r
        where r.installation_id=p_installation_id and r.retired_at is null
      ) current_binding on true
      where own.installation_id=p_installation_id for update of own;
    if found then
      v_owner:=v_ownership_decision.owner_row;
      v_installation_conflict:=v_ownership_decision.installation_conflict;
      v_conflicting_registration_id:=case when v_installation_conflict
        then v_ownership_decision.conflicting_registration_id else null end;
    else
      v_owner:=null;v_installation_conflict:=false;v_conflicting_registration_id:=null;
    end if;
    perform set_config('lock_timeout',v_observation_lock_timeout,true);
  exception when others then
    -- The failed subtransaction restores its SET LOCAL automatically. Fall back
    -- to the ORIGINAL ownership decision, with no later identity inference.
    v_conflicting_registration_id:=null;
    select * into v_owner from app.pos_order_alert_installation_owners where installation_id=p_installation_id for update;
    v_installation_conflict:=found and (v_owner.device_id<>p_device_id
      or v_owner.organization_id<>(v_context->>'organization_id')::uuid
      or v_owner.restaurant_id<>(v_context->>'restaurant_id')::uuid
      or v_owner.branch_id<>(v_context->>'branch_id')::uuid);
  end;$new_decision$);

 if length(v_replacement)-length(replace(v_replacement,$old_refusal$  if v_installation_conflict then
    begin
      perform app.record_pos_alert_registration_rejection(v_attempt,'INSTALLATION_CONFLICT',
        v_installation_valid,v_secret_valid,v_token_length_valid,v_token_forbidden,true,null,
        (v_context->>'organization_id')::uuid,(v_context->>'restaurant_id')::uuid,
        (v_context->>'branch_id')::uuid,p_device_id,(v_context->>'device_session_id')::uuid);
    exception when others then null;
    end;
    return jsonb_build_object('ok',false,'error','invalid_request'); end if;$old_refusal$,''))<>length($old_refusal$  if v_installation_conflict then
    begin
      perform app.record_pos_alert_registration_rejection(v_attempt,'INSTALLATION_CONFLICT',
        v_installation_valid,v_secret_valid,v_token_length_valid,v_token_forbidden,true,null,
        (v_context->>'organization_id')::uuid,(v_context->>'restaurant_id')::uuid,
        (v_context->>'branch_id')::uuid,p_device_id,(v_context->>'device_session_id')::uuid);
    exception when others then null;
    end;
    return jsonb_build_object('ok',false,'error','invalid_request'); end if;$old_refusal$) then
  raise exception 'reviewed alert diagnostic patch differs' using errcode='55000';
 end if;
 v_replacement:=replace(v_replacement,$old_refusal$  if v_installation_conflict then
    begin
      perform app.record_pos_alert_registration_rejection(v_attempt,'INSTALLATION_CONFLICT',
        v_installation_valid,v_secret_valid,v_token_length_valid,v_token_forbidden,true,null,
        (v_context->>'organization_id')::uuid,(v_context->>'restaurant_id')::uuid,
        (v_context->>'branch_id')::uuid,p_device_id,(v_context->>'device_session_id')::uuid);
    exception when others then null;
    end;
    return jsonb_build_object('ok',false,'error','invalid_request'); end if;$old_refusal$,$new_refusal$  if v_installation_conflict then
    begin
      perform app.record_pos_alert_registration_rejection(v_attempt,'INSTALLATION_CONFLICT',
        v_installation_valid,v_secret_valid,v_token_length_valid,v_token_forbidden,true,null,
        (v_context->>'organization_id')::uuid,(v_context->>'restaurant_id')::uuid,
        (v_context->>'branch_id')::uuid,p_device_id,(v_context->>'device_session_id')::uuid);
    exception when others then null;
    end;
    -- Keep this separate from classification: a diagnostic FK/sink failure must
    -- not roll back the already established refusal classification.
    begin
      perform app.record_pos_alert_conflicting_registration(v_attempt,v_conflicting_registration_id,
        (v_context->>'organization_id')::uuid,(v_context->>'restaurant_id')::uuid,
        (v_context->>'branch_id')::uuid,p_device_id,(v_context->>'device_session_id')::uuid);
    exception when others or query_canceled then null;
    end;
    return jsonb_build_object('ok',false,'error','invalid_request'); end if;$new_refusal$);
 if length(v_definition)-length(replace(v_definition,v_source,''))<>length(v_source) then
  raise exception 'reviewed alert definition differs' using errcode='55000';
 end if;
 execute replace(v_definition,v_source,v_replacement);
end;
$patch$;

commit;
