-- BIZBOT-STOREFRONT-SEO-CONSENT-001. Consent storage only; indexing stays OFF.
-- Additive private state/receipts; no legacy profile, menu, ordering or device changes.
begin;

create table app.restaurant_storefront_seo_consent_v1 (
  organization_id uuid not null,
  restaurant_id uuid not null,
  consent_enabled boolean not null default false,
  revision bigint not null check(revision>0),
  updated_by_app_user_id uuid not null references public.app_users(id) on delete restrict,
  updated_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  primary key(organization_id,restaurant_id),
  foreign key(organization_id,restaurant_id) references public.restaurants(organization_id,id) on delete restrict
);
comment on table app.restaurant_storefront_seo_consent_v1 is
  'Restaurant-level explicit consent, independent of publication/branch/intake. Missing row means OFF at revision 0. No backfill, publication inference or indexing activation. Tombstones/suspension retain history; eligibility always checks live parents.';

create table app.storefront_seo_consent_requests_v1 (
  actor_app_user_id uuid not null references public.app_users(id) on delete restrict,
  client_request_id uuid not null,
  organization_id uuid not null,
  restaurant_id uuid not null,
  operation text not null check(operation='set_storefront_seo_consent_v1'),
  request_fingerprint text not null check(request_fingerprint ~ '^[a-f0-9]{64}$'),
  result jsonb not null check(jsonb_typeof(result)='object'),
  created_at timestamptz not null default clock_timestamp(),
  primary key(actor_app_user_id,client_request_id),
  foreign key(organization_id,restaurant_id) references public.restaurants(organization_id,id) on delete restrict
);

alter table app.restaurant_storefront_seo_consent_v1 enable row level security;
alter table app.restaurant_storefront_seo_consent_v1 force row level security;
alter table app.storefront_seo_consent_requests_v1 enable row level security;
alter table app.storefront_seo_consent_requests_v1 force row level security;
revoke all on app.restaurant_storefront_seo_consent_v1,app.storefront_seo_consent_requests_v1 from public,anon,authenticated,service_role;
create policy storefront_seo_consent_v1_select_deny on app.restaurant_storefront_seo_consent_v1 for select to authenticated using(false);
create policy storefront_seo_consent_v1_insert_deny on app.restaurant_storefront_seo_consent_v1 for insert to authenticated with check(false);
create policy storefront_seo_consent_v1_update_deny on app.restaurant_storefront_seo_consent_v1 for update to authenticated using(false) with check(false);
create policy storefront_seo_consent_v1_delete_deny on app.restaurant_storefront_seo_consent_v1 for delete to authenticated using(false);
create policy storefront_seo_consent_requests_v1_select_deny on app.storefront_seo_consent_requests_v1 for select to authenticated using(false);
create policy storefront_seo_consent_requests_v1_insert_deny on app.storefront_seo_consent_requests_v1 for insert to authenticated with check(false);
create policy storefront_seo_consent_requests_v1_update_deny on app.storefront_seo_consent_requests_v1 for update to authenticated using(false) with check(false);
create policy storefront_seo_consent_requests_v1_delete_deny on app.storefront_seo_consent_requests_v1 for delete to authenticated using(false);
create trigger storefront_seo_consent_requests_v1_append_only before update or delete on app.storefront_seo_consent_requests_v1
  for each row execute function app.enforce_audit_append_only();
create trigger storefront_seo_consent_requests_v1_no_truncate before truncate on app.storefront_seo_consent_requests_v1
  for each statement execute function app.enforce_audit_append_only();

-- PRIVATE candidate predicate for a separately approved future release. This
-- neither activates indexing nor grants an anonymous read/enumeration surface.
-- Operational pause/opening hours/intake are deliberately not consent inputs.
create function app.storefront_seo_eligibility_when_released_v1(p_organization_id uuid,p_restaurant_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from app.restaurant_storefront_seo_consent_v1 c
    join public.organizations o on o.id=c.organization_id
    join public.restaurants r on (r.organization_id,r.id)=(c.organization_id,c.restaurant_id)
    join public.restaurant_storefront_profiles p on (p.organization_id,p.restaurant_id)=(c.organization_id,c.restaurant_id)
    join public.branches b on (b.organization_id,b.restaurant_id,b.id)=(p.organization_id,p.restaurant_id,p.storefront_branch_id)
    where (c.organization_id,c.restaurant_id)=(p_organization_id,p_restaurant_id) and c.consent_enabled
      and o.status='active' and o.deleted_at is null and r.status='active' and r.deleted_at is null
      and p.is_published and p.deleted_at is null and b.status='active' and b.deleted_at is null);
$$;
revoke all on function app.storefront_seo_eligibility_when_released_v1(uuid,uuid) from public,anon,authenticated,service_role;

-- No identity, organization GUC, role, timestamp or branch is client-supplied.
-- Locked order is organization -> restaurant -> sorted covering memberships.
-- The restaurant lock fences absent-row provisioning and legacy publication
-- writes. This feature never acquires a kitchen/notification/printing lock.
create function app.storefront_seo_consent_authorize_v1(p_organization_id uuid,p_restaurant_id uuid,p_min_rank integer,p_lock text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=app.current_app_user_id();rank_value integer;
begin
  if auth.uid() is null or actor is null then raise exception 'storefront SEO consent authentication required' using errcode='42501';end if;
  if p_organization_id is null or p_restaurant_id is null then
    return jsonb_build_object('ok',false,'error','invalid_request','entity','storefront_seo_consent');
  end if;
  if p_lock<>'none' then
    perform 1 from public.organizations o where o.id=p_organization_id and o.status='active' and o.deleted_at is null for share;
    if not found then return jsonb_build_object('ok',false,'error','not_found','entity','storefront_seo_consent');end if;
    if p_lock='update' then
      perform 1 from public.restaurants r where (r.organization_id,r.id)=(p_organization_id,p_restaurant_id)
        and r.status='active' and r.deleted_at is null for update;
    else
      perform 1 from public.restaurants r where (r.organization_id,r.id)=(p_organization_id,p_restaurant_id)
        and r.status='active' and r.deleted_at is null for share;
    end if;
    if not found then return jsonb_build_object('ok',false,'error','not_found','entity','storefront_seo_consent');end if;
    perform 1 from public.memberships m where m.app_user_id=actor and m.organization_id=p_organization_id
      and m.status='active' and m.deleted_at is null and (m.restaurant_id is null or m.restaurant_id=p_restaurant_id)
      and m.branch_id is null order by m.id for share;
  else
    perform 1 from public.restaurants r join public.organizations o on o.id=r.organization_id
      where (r.organization_id,r.id)=(p_organization_id,p_restaurant_id)
        and r.status='active' and r.deleted_at is null and o.status='active' and o.deleted_at is null;
    if not found then return jsonb_build_object('ok',false,'error','not_found','entity','storefront_seo_consent');end if;
  end if;
  rank_value:=app.actor_rank_in_scope(p_organization_id,p_restaurant_id,null);
  if rank_value=0 then return jsonb_build_object('ok',false,'error','not_found','entity','storefront_seo_consent');end if;
  if rank_value<p_min_rank then return jsonb_build_object('ok',false,'error','permission_denied','entity','storefront_seo_consent');end if;
  return jsonb_build_object('ok',true,'can_manage',rank_value>=3);
end; $$;
revoke all on function app.storefront_seo_consent_authorize_v1(uuid,uuid,integer,text) from public,anon,authenticated,service_role;

-- Only call after exact scope authorization. Sequence values are decimal
-- strings so JavaScript/Dart clients cannot round a bigint revision.
create function app.storefront_seo_consent_state_v1(p_organization_id uuid,p_restaurant_id uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('ok',true,'entity','storefront_seo_consent',
    'organization_id',p_organization_id,'restaurant_id',p_restaurant_id,
    'provisioned',c.restaurant_id is not null,'consent_enabled',coalesce(c.consent_enabled,false),
    'revision',coalesce(c.revision,0)::text,'can_manage',app.actor_rank_in_scope(p_organization_id,p_restaurant_id,null)>=3,
    'indexing_active',false,'effective_indexing_eligible',false,
    'updated_at',c.updated_at,'updated_by_app_user_id',c.updated_by_app_user_id)
  from (values(1)) seed(n) left join app.restaurant_storefront_seo_consent_v1 c
    on (c.organization_id,c.restaurant_id)=(p_organization_id,p_restaurant_id);
$$;
revoke all on function app.storefront_seo_consent_state_v1(uuid,uuid) from public,anon,authenticated,service_role;

create function app.storefront_seo_consent_intent_v1(p_organization_id uuid,p_restaurant_id uuid,p_expected_revision bigint,p_consent_enabled boolean)
returns text language sql immutable set search_path='' as $$
  select encode(sha256(convert_to(jsonb_build_object('operation','set_storefront_seo_consent_v1',
    'organization_id',p_organization_id,'restaurant_id',p_restaurant_id,
    'expected_revision',p_expected_revision::text,'consent_enabled',p_consent_enabled)::text,'UTF8')),'hex');
$$;
revoke all on function app.storefront_seo_consent_intent_v1(uuid,uuid,bigint,boolean) from public,anon,authenticated,service_role;

create function app.get_storefront_seo_consent_v1(p_organization_id uuid,p_restaurant_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare authority jsonb;
begin
  authority:=app.storefront_seo_consent_authorize_v1(p_organization_id,p_restaurant_id,2,'none');
  if authority->>'ok' is distinct from 'true' then return authority;end if;
  authority:=app.storefront_seo_consent_authorize_v1(p_organization_id,p_restaurant_id,2,'share');
  if authority->>'ok' is distinct from 'true' then return authority;end if;
  return app.storefront_seo_consent_state_v1(p_organization_id,p_restaurant_id);
end; $$;

create function app.set_storefront_seo_consent_v1(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_expected_revision bigint,p_consent_enabled boolean)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=app.current_app_user_id();authority jsonb;fingerprint text;ledger app.storefront_seo_consent_requests_v1;
  before_state jsonb;result jsonb;old_consent app.restaurant_storefront_seo_consent_v1;changed boolean;decision_at timestamptz;
begin
  authority:=app.storefront_seo_consent_authorize_v1(p_organization_id,p_restaurant_id,3,'none');
  if authority->>'ok' is distinct from 'true' then
    if authority->>'error'='permission_denied' then
      perform app.management_audit(p_organization_id,p_restaurant_id,null,'settings.storefront.seo_consent.denied',null,
        jsonb_build_object('setting','storefront_seo_consent'));
    end if;
    return authority;
  end if;
  if p_client_request_id is null or p_expected_revision is null or p_expected_revision<0 or p_consent_enabled is null then
    return jsonb_build_object('ok',false,'error','invalid_request','entity','storefront_seo_consent');
  end if;
  fingerprint:=app.storefront_seo_consent_intent_v1(p_organization_id,p_restaurant_id,p_expected_revision,p_consent_enabled);
  -- Actor+UUID fencing precedes all hierarchy locks, even across scopes. A
  -- private receipt lane never waits on the legacy management ledger.
  perform pg_advisory_xact_lock(hashtextextended('storefront-seo-consent-v1:'||actor::text||':'||p_client_request_id::text,0));
  authority:=app.storefront_seo_consent_authorize_v1(p_organization_id,p_restaurant_id,3,'update');
  if authority->>'ok' is distinct from 'true' then
    if authority->>'error'='permission_denied' then
      perform app.management_audit(p_organization_id,p_restaurant_id,null,'settings.storefront.seo_consent.denied',null,
        jsonb_build_object('setting','storefront_seo_consent'));
    end if;
    return authority;
  end if;
  select * into old_consent from app.restaurant_storefront_seo_consent_v1 c
    where (c.organization_id,c.restaurant_id)=(p_organization_id,p_restaurant_id) for update;
  select * into ledger from app.storefront_seo_consent_requests_v1 q where q.actor_app_user_id=actor and q.client_request_id=p_client_request_id;
  if found then
    if ledger.request_fingerprint<>fingerprint then return jsonb_build_object('ok',false,'error','request_conflict','entity','storefront_seo_consent');end if;
    return ledger.result||jsonb_build_object('idempotent_replay',true);
  end if;
  before_state:=app.storefront_seo_consent_state_v1(p_organization_id,p_restaurant_id);
  if p_expected_revision<>(before_state->>'revision')::bigint then
    result:=jsonb_build_object('ok',false,'error','revision_conflict','entity','storefront_seo_consent',
      'organization_id',p_organization_id,'restaurant_id',p_restaurant_id,
      'client_request_id',p_client_request_id,'idempotent_replay',false,'current',before_state);
    insert into app.storefront_seo_consent_requests_v1(actor_app_user_id,client_request_id,organization_id,restaurant_id,operation,request_fingerprint,result)
      values(actor,p_client_request_id,p_organization_id,p_restaurant_id,'set_storefront_seo_consent_v1',fingerprint,result);
    return result;
  end if;
  changed:=old_consent.restaurant_id is null or old_consent.consent_enabled is distinct from p_consent_enabled;
  if changed then
    decision_at:=clock_timestamp();
    insert into app.restaurant_storefront_seo_consent_v1(organization_id,restaurant_id,consent_enabled,revision,updated_by_app_user_id,updated_at)
      values(p_organization_id,p_restaurant_id,p_consent_enabled,p_expected_revision+1,actor,decision_at)
      on conflict(organization_id,restaurant_id) do update set consent_enabled=excluded.consent_enabled,revision=excluded.revision,
        updated_by_app_user_id=excluded.updated_by_app_user_id,updated_at=excluded.updated_at;
  end if;
  result:=app.storefront_seo_consent_state_v1(p_organization_id,p_restaurant_id)||jsonb_build_object(
    'client_request_id',p_client_request_id,'idempotent_replay',false,'no_change',not changed);
  insert into app.storefront_seo_consent_requests_v1(actor_app_user_id,client_request_id,organization_id,restaurant_id,operation,request_fingerprint,result)
    values(actor,p_client_request_id,p_organization_id,p_restaurant_id,'set_storefront_seo_consent_v1',fingerprint,result);
  if changed then
    perform app.management_audit(p_organization_id,p_restaurant_id,null,'settings.storefront.seo_consent.updated',
      before_state-'ok'-'entity',result-'ok'-'entity'-'idempotent_replay'-'no_change');
  end if;
  return result;
end; $$;

-- Read-only receipt recovery. not_recorded is a point-in-time answer: a delayed
-- original request could still arrive. Explicit retry must retain UUID+intent.
create function app.reconcile_storefront_seo_consent_v1(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_expected_revision bigint,p_consent_enabled boolean)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare actor uuid:=app.current_app_user_id();authority jsonb;fingerprint text;ledger app.storefront_seo_consent_requests_v1;
begin
  authority:=app.storefront_seo_consent_authorize_v1(p_organization_id,p_restaurant_id,3,'none');
  if authority->>'ok' is distinct from 'true' then return authority;end if;
  if p_client_request_id is null or p_expected_revision is null or p_expected_revision<0 or p_consent_enabled is null then
    return jsonb_build_object('ok',false,'error','invalid_request','entity','storefront_seo_consent');
  end if;
  fingerprint:=app.storefront_seo_consent_intent_v1(p_organization_id,p_restaurant_id,p_expected_revision,p_consent_enabled);
  perform pg_advisory_xact_lock(hashtextextended('storefront-seo-consent-v1:'||actor::text||':'||p_client_request_id::text,0));
  authority:=app.storefront_seo_consent_authorize_v1(p_organization_id,p_restaurant_id,3,'share');
  if authority->>'ok' is distinct from 'true' then return authority;end if;
  select * into ledger from app.storefront_seo_consent_requests_v1 q where q.actor_app_user_id=actor and q.client_request_id=p_client_request_id;
  if found then
    if ledger.request_fingerprint<>fingerprint then return jsonb_build_object('ok',false,'error','request_conflict','entity','storefront_seo_consent');end if;
    return jsonb_build_object('ok',true,'entity','storefront_seo_consent','organization_id',p_organization_id,'restaurant_id',p_restaurant_id,
      'mutation_state',case when ledger.result->>'ok'='true' then 'committed' else 'refused' end,
      'result',ledger.result||jsonb_build_object('idempotent_replay',true),
      'current',app.storefront_seo_consent_state_v1(p_organization_id,p_restaurant_id));
  end if;
  return jsonb_build_object('ok',true,'entity','storefront_seo_consent','organization_id',p_organization_id,'restaurant_id',p_restaurant_id,
    'mutation_state','not_recorded','result',null,'current',app.storefront_seo_consent_state_v1(p_organization_id,p_restaurant_id));
end; $$;

create function public.get_storefront_seo_consent_v1(p_organization_id uuid,p_restaurant_id uuid)
returns jsonb language sql volatile security invoker set search_path='' as $$select app.get_storefront_seo_consent_v1(p_organization_id,p_restaurant_id);$$;
create function public.set_storefront_seo_consent_v1(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_expected_revision bigint,p_consent_enabled boolean)
returns jsonb language sql volatile security invoker set search_path='' as $$select app.set_storefront_seo_consent_v1(p_client_request_id,p_organization_id,p_restaurant_id,p_expected_revision,p_consent_enabled);$$;
create function public.reconcile_storefront_seo_consent_v1(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_expected_revision bigint,p_consent_enabled boolean)
returns jsonb language sql volatile security invoker set search_path='' as $$select app.reconcile_storefront_seo_consent_v1(p_client_request_id,p_organization_id,p_restaurant_id,p_expected_revision,p_consent_enabled);$$;

revoke all on function app.get_storefront_seo_consent_v1(uuid,uuid),public.get_storefront_seo_consent_v1(uuid,uuid),
  app.set_storefront_seo_consent_v1(uuid,uuid,uuid,bigint,boolean),public.set_storefront_seo_consent_v1(uuid,uuid,uuid,bigint,boolean),
  app.reconcile_storefront_seo_consent_v1(uuid,uuid,uuid,bigint,boolean),public.reconcile_storefront_seo_consent_v1(uuid,uuid,uuid,bigint,boolean)
  from public,anon,authenticated,service_role;
grant execute on function app.get_storefront_seo_consent_v1(uuid,uuid),public.get_storefront_seo_consent_v1(uuid,uuid),
  app.set_storefront_seo_consent_v1(uuid,uuid,uuid,bigint,boolean),public.set_storefront_seo_consent_v1(uuid,uuid,uuid,bigint,boolean),
  app.reconcile_storefront_seo_consent_v1(uuid,uuid,uuid,bigint,boolean),public.reconcile_storefront_seo_consent_v1(uuid,uuid,uuid,bigint,boolean)
  to authenticated;

commit;
