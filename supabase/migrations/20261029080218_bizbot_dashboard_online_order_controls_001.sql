-- BIZBOT-DASHBOARD-ONLINE-ORDER-CONTROLS-001.
-- Additive manager/owner API. Legacy 353 functions and all notification,
-- request, delivery, hold, lease and printer records remain unchanged.
begin;

-- Feature-owned receipts avoid changing the lock order of the shared legacy
-- management ledger. Different APIs cannot hold a receipt lock while waiting
-- on this API's hierarchy locks (or vice versa).
create table app.online_order_settings_requests_v2 (
  actor_app_user_id uuid not null references public.app_users(id),
  client_request_id uuid not null,
  organization_id uuid not null,
  restaurant_id uuid not null,
  branch_id uuid not null,
  operation text not null check(operation='set_online_order_settings_v2'),
  request_fingerprint text not null check(request_fingerprint ~ '^[a-f0-9]{64}$'),
  result jsonb not null check(jsonb_typeof(result)='object'),
  created_at timestamptz not null default clock_timestamp(),
  primary key(actor_app_user_id,client_request_id),
  foreign key(organization_id,restaurant_id,branch_id) references public.branches(organization_id,restaurant_id,id)
);
alter table app.online_order_settings_requests_v2 enable row level security;
alter table app.online_order_settings_requests_v2 force row level security;
revoke all on app.online_order_settings_requests_v2 from public,anon,authenticated,service_role;
create policy online_order_settings_requests_v2_select_deny on app.online_order_settings_requests_v2 for select to authenticated using(false);
create policy online_order_settings_requests_v2_insert_deny on app.online_order_settings_requests_v2 for insert to authenticated with check(false);
create policy online_order_settings_requests_v2_update_deny on app.online_order_settings_requests_v2 for update to authenticated using(false) with check(false);
create policy online_order_settings_requests_v2_delete_deny on app.online_order_settings_requests_v2 for delete to authenticated using(false);
create trigger online_order_settings_requests_v2_append_only before update or delete on app.online_order_settings_requests_v2
  for each row execute function app.enforce_audit_append_only();
create trigger online_order_settings_requests_v2_no_truncate before truncate on app.online_order_settings_requests_v2
  for each statement execute function app.enforce_audit_append_only();

-- Private projection. Callers must authorize the exact ancestry first.
-- Decimal strings preserve sequence values in Dart/JavaScript clients.
create function app.online_order_settings_state_v2(p_organization_id uuid,p_restaurant_id uuid,p_branch_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('ok',true,'entity','online_order_settings',
    'organization_id',p_organization_id,'restaurant_id',p_restaurant_id,'branch_id',p_branch_id,
    'provisioned',s.branch_id is not null,
    'ordering_enabled',coalesce(s.ordering_enabled,true),
    'printing_enabled',coalesce(s.printing_enabled,true),
    'alerts_enabled',coalesce(s.alerts_enabled,true),
    'revision',coalesce(s.revision,0)::text,
    'print_generation',coalesce(s.print_generation,0)::text,
    'containment_revision',coalesce(s.containment_revision,0)::text,
    'intake_channel_provisioned',c.branch_id is not null,'intake_channel_enabled',c.submission_enabled)
  from (values(1)) seed(n) left join app.online_order_settings s
    on (s.organization_id,s.restaurant_id,s.branch_id)=(p_organization_id,p_restaurant_id,p_branch_id)
  left join public.web_order_channel_settings c
    on (c.organization_id,c.restaurant_id,c.branch_id)=(p_organization_id,p_restaurant_id,p_branch_id);
$$;
revoke all on function app.online_order_settings_state_v2(uuid,uuid,uuid) from public,anon,authenticated,service_role;

-- This is the same downward-only human membership authority as 353, with an
-- explicit ancestry check before any audit or result-ledger lookup. No org GUC,
-- device/PIN capability, platform support mode or caller-supplied actor is used.
-- Locked callers acquire the containment fence BEFORE calling this helper.
create function app.online_order_settings_authorize_v2(p_organization_id uuid,p_restaurant_id uuid,p_branch_id uuid,p_lock boolean)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=app.current_app_user_id();rank_value integer;
begin
  if auth.uid() is null or actor is null then raise exception 'online order settings authentication required' using errcode='42501';end if;
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    return jsonb_build_object('ok',false,'error','invalid_request','entity','online_order_settings');
  end if;
  if p_lock then
    perform 1 from public.branches b
      join public.restaurants r on (r.organization_id,r.id)=(b.organization_id,b.restaurant_id)
      join public.organizations o on o.id=b.organization_id
      where (b.organization_id,b.restaurant_id,b.id)=(p_organization_id,p_restaurant_id,p_branch_id)
        and b.status='active' and b.deleted_at is null and r.status='active' and r.deleted_at is null
        and o.status='active' and o.deleted_at is null for share of b,r,o;
  else
    perform 1 from public.branches b
      join public.restaurants r on (r.organization_id,r.id)=(b.organization_id,b.restaurant_id)
      join public.organizations o on o.id=b.organization_id
      where (b.organization_id,b.restaurant_id,b.id)=(p_organization_id,p_restaurant_id,p_branch_id)
        and b.status='active' and b.deleted_at is null and r.status='active' and r.deleted_at is null
        and o.status='active' and o.deleted_at is null;
  end if;
  if not found then return jsonb_build_object('ok',false,'error','not_found','entity','online_order_settings');end if;
  if p_lock then
    -- Stabilize every currently covering membership; sorted locks avoid
    -- different member-order acquisition between simultaneous branch saves.
    perform 1 from public.memberships m where m.app_user_id=actor and m.organization_id=p_organization_id
      and m.status='active' and m.deleted_at is null
      and (m.restaurant_id is null or m.restaurant_id=p_restaurant_id)
      and (m.branch_id is null or m.branch_id=p_branch_id) order by m.id for share;
  end if;
  rank_value:=app.actor_rank_in_scope(p_organization_id,p_restaurant_id,p_branch_id);
  if rank_value=0 then return jsonb_build_object('ok',false,'error','not_found','entity','online_order_settings');end if;
  if rank_value<2 then return jsonb_build_object('ok',false,'error','permission_denied','entity','online_order_settings');end if;
  return jsonb_build_object('ok',true);
end; $$;
revoke all on function app.online_order_settings_authorize_v2(uuid,uuid,uuid,boolean) from public,anon,authenticated,service_role;

create function app.online_order_settings_intent_v2(p_organization_id uuid,p_restaurant_id uuid,p_branch_id uuid,
  p_expected_revision bigint,p_ordering_enabled boolean,p_printing_enabled boolean,p_alerts_enabled boolean)
returns text language sql immutable set search_path='' as $$
  select encode(sha256(convert_to(jsonb_build_object('operation','set_online_order_settings_v2',
    'organization_id',p_organization_id,'restaurant_id',p_restaurant_id,'branch_id',p_branch_id,
    'expected_revision',p_expected_revision::text,'ordering_enabled',p_ordering_enabled,
    'printing_enabled',p_printing_enabled,'alerts_enabled',p_alerts_enabled)::text,'UTF8')),'hex');
$$;
revoke all on function app.online_order_settings_intent_v2(uuid,uuid,uuid,bigint,boolean,boolean,boolean) from public,anon,authenticated,service_role;

-- The protected feature-owned ledger binds valid confirmed intents,
-- including CAS refusals. Refusal receipts are not configuration writes.
create function app.online_order_settings_claim_v2(p_actor uuid,p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_branch_id uuid,p_fingerprint text,p_result jsonb)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare claimed boolean;ledger app.online_order_settings_requests_v2;
begin
  insert into app.online_order_settings_requests_v2(actor_app_user_id,client_request_id,organization_id,restaurant_id,branch_id,operation,request_fingerprint,result)
    values(p_actor,p_client_request_id,p_organization_id,p_restaurant_id,p_branch_id,'set_online_order_settings_v2',p_fingerprint,p_result)
    on conflict(actor_app_user_id,client_request_id) do nothing returning true into claimed;
  if coalesce(claimed,false) then return null;end if;
  select * into strict ledger from app.online_order_settings_requests_v2 m
    where m.actor_app_user_id=p_actor and m.client_request_id=p_client_request_id;
  if ledger.operation<>'set_online_order_settings_v2' or ledger.request_fingerprint<>p_fingerprint then
    return jsonb_build_object('ok',false,'error','request_conflict','entity','online_order_settings');
  end if;
  return ledger.result||jsonb_build_object('idempotent_replay',true);
end; $$;
revoke all on function app.online_order_settings_claim_v2(uuid,uuid,uuid,uuid,uuid,text,jsonb) from public,anon,authenticated,service_role;

create function app.get_online_order_settings_v2(p_organization_id uuid,p_restaurant_id uuid,p_branch_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare authority jsonb;
begin
  authority:=app.online_order_settings_authorize_v2(p_organization_id,p_restaurant_id,p_branch_id,false);
  if authority->>'ok' is distinct from 'true' then return authority;end if;
  perform app.lock_kitchen_print_containment(p_branch_id,false);
  authority:=app.online_order_settings_authorize_v2(p_organization_id,p_restaurant_id,p_branch_id,true);
  if authority->>'ok' is distinct from 'true' then return authority;end if;
  return app.online_order_settings_state_v2(p_organization_id,p_restaurant_id,p_branch_id);
end; $$;

create function app.set_online_order_settings_v2(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_branch_id uuid,
  p_expected_revision bigint,p_ordering_enabled boolean,p_printing_enabled boolean,p_alerts_enabled boolean)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=app.current_app_user_id();authority jsonb;before_state jsonb;result jsonb;
  old_settings app.online_order_settings;ledger app.online_order_settings_requests_v2;fingerprint text;
  base jsonb;new_revision bigint;new_generation bigint;changed boolean;ordering_changed boolean;replay jsonb;channel_enabled boolean;channel_found boolean;
begin
  authority:=app.online_order_settings_authorize_v2(p_organization_id,p_restaurant_id,p_branch_id,false);
  if authority->>'ok' is distinct from 'true' then
    if authority->>'error'='permission_denied' then
      perform app.management_audit(p_organization_id,p_restaurant_id,p_branch_id,'settings.online_orders.denied',null,
        jsonb_build_object('setting','online_orders'));
    end if;
    return authority;
  end if;
  if p_client_request_id is null or p_expected_revision is null or p_expected_revision<0
    or p_ordering_enabled is null or p_printing_enabled is null or p_alerts_enabled is null then
    return jsonb_build_object('ok',false,'error','invalid_request','entity','online_order_settings');
  end if;
  fingerprint:=app.online_order_settings_intent_v2(p_organization_id,p_restaurant_id,p_branch_id,
    p_expected_revision,p_ordering_enabled,p_printing_enabled,p_alerts_enabled);
  -- All v2 operations use request -> containment -> hierarchy -> membership
  -- -> settings -> ledger. Legacy 353 shares containment -> hierarchy/settings.
  -- A same-UUID request on another branch cannot invert those locks.
  perform pg_advisory_xact_lock(hashtextextended('online-order-settings-v2:'||actor::text||':'||p_client_request_id::text,0));
  perform app.lock_kitchen_print_containment(p_branch_id,true);
  authority:=app.online_order_settings_authorize_v2(p_organization_id,p_restaurant_id,p_branch_id,true);
  if authority->>'ok' is distinct from 'true' then return authority;end if;
  select * into old_settings from app.online_order_settings s where
    (s.organization_id,s.restaurant_id,s.branch_id)=(p_organization_id,p_restaurant_id,p_branch_id) for update;
  select * into ledger from app.online_order_settings_requests_v2 m
    where m.actor_app_user_id=actor and m.client_request_id=p_client_request_id;
  -- Exact replay is resolved BEFORE the current CAS; it never rewrites a later
  -- manager's values or returns a receipt for a different scope/intent.
  if found then
    if ledger.operation<>'set_online_order_settings_v2' or ledger.request_fingerprint<>fingerprint then
      return jsonb_build_object('ok',false,'error','request_conflict','entity','online_order_settings');
    end if;
    return ledger.result||jsonb_build_object('idempotent_replay',true);
  end if;
  before_state:=app.online_order_settings_state_v2(p_organization_id,p_restaurant_id,p_branch_id);
  if p_expected_revision<>(before_state->>'revision')::bigint then
    result:=jsonb_build_object('ok',false,'error','revision_conflict','entity','online_order_settings',
      'client_request_id',p_client_request_id,'idempotent_replay',false,'current',before_state);
    replay:=app.online_order_settings_claim_v2(actor,p_client_request_id,p_organization_id,p_restaurant_id,p_branch_id,fingerprint,result);
    return coalesce(replay,result);
  end if;
  select c.submission_enabled into channel_enabled from public.web_order_channel_settings c
    where (c.organization_id,c.restaurant_id,c.branch_id)=(p_organization_id,p_restaurant_id,p_branch_id) for update;
  channel_found:=found;
  ordering_changed:=p_ordering_enabled is distinct from coalesce(old_settings.ordering_enabled,true);
  base:=app.kitchen_print_containment_state(p_organization_id,p_restaurant_id,p_branch_id);
  changed:=old_settings.branch_id is null
    or row(old_settings.ordering_enabled,old_settings.printing_enabled,old_settings.alerts_enabled,old_settings.containment_revision)
      is distinct from row(p_ordering_enabled,p_printing_enabled,p_alerts_enabled,(base->>'revision')::bigint);
  if changed then
    new_revision:=nextval('app.kitchen_print_containment_revision');
    new_generation:=case when old_settings.branch_id is not null and old_settings.printing_enabled=p_printing_enabled
      and old_settings.containment_revision=(base->>'revision')::bigint then old_settings.print_generation else new_revision end;
  else new_revision:=old_settings.revision;new_generation:=old_settings.print_generation;
  end if;
  result:=jsonb_build_object('ok',true,'entity','online_order_settings','organization_id',p_organization_id,
    'restaurant_id',p_restaurant_id,'branch_id',p_branch_id,'provisioned',true,'ordering_enabled',p_ordering_enabled,
    'printing_enabled',p_printing_enabled,'alerts_enabled',p_alerts_enabled,'revision',new_revision::text,
    'print_generation',new_generation::text,'containment_revision',base->>'revision',
    'intake_channel_provisioned',channel_found,'intake_channel_enabled',
      case when channel_found and ordering_changed then p_ordering_enabled else channel_enabled end,
    'client_request_id',p_client_request_id,'idempotent_replay',false,'no_change',not changed);
  -- Claim first in the feature-owned receipt table. No legacy API/table is
  -- changed, and no receipt from another operation can be reinterpreted here.
  begin
  replay:=app.online_order_settings_claim_v2(actor,p_client_request_id,p_organization_id,p_restaurant_id,p_branch_id,fingerprint,result);
  if replay is not null then return replay;end if;
  if not changed then return result;end if;
  -- The exact 353 generation rule is preserved: only printing eligibility or
  -- containment revision changes rotate generation, including a flag no-op
  -- after a containment change. No historical request/lease is re-enrolled.
  insert into app.online_order_settings(organization_id,restaurant_id,branch_id,ordering_enabled,printing_enabled,
    alerts_enabled,revision,print_generation,containment_revision)
    values(p_organization_id,p_restaurant_id,p_branch_id,p_ordering_enabled,p_printing_enabled,p_alerts_enabled,
      new_revision,new_generation,(base->>'revision')::bigint)
    on conflict(branch_id) do update set ordering_enabled=excluded.ordering_enabled,printing_enabled=excluded.printing_enabled,
      alerts_enabled=excluded.alerts_enabled,revision=excluded.revision,print_generation=excluded.print_generation,
      containment_revision=excluded.containment_revision,updated_at=clock_timestamp()
    where app.online_order_settings.organization_id=p_organization_id and app.online_order_settings.restaurant_id=p_restaurant_id
      and app.online_order_settings.revision=coalesce(old_settings.revision,0)
    returning * into old_settings;
  if not found then raise exception 'online order settings changed during provisioning' using errcode='P2001';end if;
  -- Independent alerts/printing saves never change an intake channel. A branch
  -- without a published storefront legitimately has no channel; publication
  -- retains its existing provisioning trigger and is never performed here.
  if channel_found and ordering_changed then
    update public.web_order_channel_settings set submission_enabled=p_ordering_enabled,updated_at=clock_timestamp()
      where organization_id=p_organization_id and restaurant_id=p_restaurant_id and branch_id=p_branch_id
        and submission_enabled=channel_enabled;
    if not found then raise exception 'online order intake changed concurrently' using errcode='P2001';end if;
  end if;
  insert into app.pos_order_alert_branch_cursors(branch_id) values(p_branch_id) on conflict do nothing;
  perform app.management_audit(p_organization_id,p_restaurant_id,p_branch_id,'settings.online_orders.updated',
    before_state-'ok'-'entity',result-'ok'-'entity'-'idempotent_replay'-'no_change');
  return result;
  exception when sqlstate 'P2001' then
    -- The subtransaction also rolls back the request claim. Nothing from a
    -- failed missing-row CAS can persist or later masquerade as a receipt.
    result:=jsonb_build_object('ok',false,'error','revision_conflict','entity','online_order_settings',
      'client_request_id',p_client_request_id,'idempotent_replay',false,
      'current',app.online_order_settings_state_v2(p_organization_id,p_restaurant_id,p_branch_id));
    replay:=app.online_order_settings_claim_v2(actor,p_client_request_id,p_organization_id,p_restaurant_id,p_branch_id,fingerprint,result);
    return coalesce(replay,result);
  end;
end; $$;

-- READ-ONLY data reconciliation. The same request fence waits for an in-flight
-- v2 transaction to finish. not_recorded is a point-in-time result, not proof a
-- delayed network request can never arrive. A UI may explicitly retry ONLY the
-- identical UUID+intent; it must never silently generate a replacement write.
create function app.reconcile_online_order_settings_v2(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_branch_id uuid,
  p_expected_revision bigint,p_ordering_enabled boolean,p_printing_enabled boolean,p_alerts_enabled boolean)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=app.current_app_user_id();authority jsonb;ledger app.online_order_settings_requests_v2;fingerprint text;
begin
  authority:=app.online_order_settings_authorize_v2(p_organization_id,p_restaurant_id,p_branch_id,false);
  if authority->>'ok' is distinct from 'true' then return authority;end if;
  if p_client_request_id is null or p_expected_revision is null or p_expected_revision<0
    or p_ordering_enabled is null or p_printing_enabled is null or p_alerts_enabled is null then
    return jsonb_build_object('ok',false,'error','invalid_request','entity','online_order_settings');
  end if;
  fingerprint:=app.online_order_settings_intent_v2(p_organization_id,p_restaurant_id,p_branch_id,
    p_expected_revision,p_ordering_enabled,p_printing_enabled,p_alerts_enabled);
  perform pg_advisory_xact_lock(hashtextextended('online-order-settings-v2:'||actor::text||':'||p_client_request_id::text,0));
  perform app.lock_kitchen_print_containment(p_branch_id,false);
  authority:=app.online_order_settings_authorize_v2(p_organization_id,p_restaurant_id,p_branch_id,true);
  if authority->>'ok' is distinct from 'true' then return authority;end if;
  select * into ledger from app.online_order_settings_requests_v2 m where m.actor_app_user_id=actor and m.client_request_id=p_client_request_id;
  if found then
    if ledger.operation<>'set_online_order_settings_v2' or ledger.request_fingerprint<>fingerprint then
      return jsonb_build_object('ok',false,'error','request_conflict','entity','online_order_settings');
    end if;
    return jsonb_build_object('ok',true,'entity','online_order_settings','mutation_state',
      case when ledger.result->>'ok'='true' then 'committed' else 'refused' end,
      'result',ledger.result||jsonb_build_object('idempotent_replay',true),
      'current',app.online_order_settings_state_v2(p_organization_id,p_restaurant_id,p_branch_id));
  end if;
  return jsonb_build_object('ok',true,'entity','online_order_settings','mutation_state','not_recorded','result',null,
    'current',app.online_order_settings_state_v2(p_organization_id,p_restaurant_id,p_branch_id));
end; $$;

create function public.get_online_order_settings_v2(p_organization_id uuid,p_restaurant_id uuid,p_branch_id uuid)
returns jsonb language sql volatile security invoker set search_path='' as $$
  select app.get_online_order_settings_v2(p_organization_id,p_restaurant_id,p_branch_id);$$;
create function public.set_online_order_settings_v2(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_branch_id uuid,
  p_expected_revision bigint,p_ordering_enabled boolean,p_printing_enabled boolean,p_alerts_enabled boolean)
returns jsonb language sql volatile security invoker set search_path='' as $$
  select app.set_online_order_settings_v2(p_client_request_id,p_organization_id,p_restaurant_id,p_branch_id,
    p_expected_revision,p_ordering_enabled,p_printing_enabled,p_alerts_enabled);$$;
create function public.reconcile_online_order_settings_v2(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_branch_id uuid,
  p_expected_revision bigint,p_ordering_enabled boolean,p_printing_enabled boolean,p_alerts_enabled boolean)
returns jsonb language sql volatile security invoker set search_path='' as $$
  select app.reconcile_online_order_settings_v2(p_client_request_id,p_organization_id,p_restaurant_id,p_branch_id,
    p_expected_revision,p_ordering_enabled,p_printing_enabled,p_alerts_enabled);$$;

revoke all on function app.get_online_order_settings_v2(uuid,uuid,uuid),public.get_online_order_settings_v2(uuid,uuid,uuid),
  app.set_online_order_settings_v2(uuid,uuid,uuid,uuid,bigint,boolean,boolean,boolean),public.set_online_order_settings_v2(uuid,uuid,uuid,uuid,bigint,boolean,boolean,boolean),
  app.reconcile_online_order_settings_v2(uuid,uuid,uuid,uuid,bigint,boolean,boolean,boolean),public.reconcile_online_order_settings_v2(uuid,uuid,uuid,uuid,bigint,boolean,boolean,boolean)
  from public,anon,authenticated,service_role;
grant execute on function app.get_online_order_settings_v2(uuid,uuid,uuid),public.get_online_order_settings_v2(uuid,uuid,uuid),
  app.set_online_order_settings_v2(uuid,uuid,uuid,uuid,bigint,boolean,boolean,boolean),public.set_online_order_settings_v2(uuid,uuid,uuid,uuid,bigint,boolean,boolean,boolean),
  app.reconcile_online_order_settings_v2(uuid,uuid,uuid,uuid,bigint,boolean,boolean,boolean),public.reconcile_online_order_settings_v2(uuid,uuid,uuid,uuid,bigint,boolean,boolean,boolean)
  to authenticated;

commit;
