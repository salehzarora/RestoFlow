-- BIZBOT-POS-LEGACY-PRINT-CONTAINMENT-001. SOURCE ONLY; no holds/backfill here.
-- A hold prohibits automatic retransmission pending review. It is NOT evidence
-- of transmission, paper, completion, acknowledgement or supersession.
begin;

create sequence app.kitchen_print_containment_revision;
revoke all on sequence app.kitchen_print_containment_revision from public,anon,authenticated,service_role;

create table public.kitchen_print_dispatch_holds (
  dispatch_id uuid primary key references public.kitchen_print_dispatches(id) on delete restrict,
  organization_id uuid not null,
  restaurant_id uuid not null,
  branch_id uuid not null,
  revision bigint not null unique default nextval('app.kitchen_print_containment_revision'),
  snapshot_at timestamptz not null,
  dispatch_fingerprint text not null check(dispatch_fingerprint ~ '^[a-f0-9]{32}$'),
  manifest_sha256 text not null check(manifest_sha256 ~ '^[a-f0-9]{64}$'),
  reason text not null check(length(btrim(reason)) between 1 and 500),
  operator_reference text not null check(length(btrim(operator_reference)) between 1 and 200),
  recorded_at timestamptz not null default clock_timestamp(),
  recorded_by text not null default session_user
);
create index kitchen_print_dispatch_holds_scope_idx on public.kitchen_print_dispatch_holds(organization_id,restaurant_id,branch_id);

-- Append-only operator policy history. Expiry is a BLOCK, never an implicit
-- return to ordinary mode. An ordinary-mode successor requires a new reviewed
-- operator action; permanent dispatch holds survive that successor.
create table public.kitchen_print_containment_policies (
  revision bigint primary key default nextval('app.kitchen_print_containment_revision'),
  organization_id uuid not null,
  restaurant_id uuid not null,
  branch_id uuid not null,
  mode text not null check(mode in ('ordinary','blocked','target_only')),
  target_request_id uuid,
  expires_at timestamptz,
  reason text not null check(length(btrim(reason)) between 1 and 500),
  operator_reference text not null check(length(btrim(operator_reference)) between 1 and 200),
  recorded_at timestamptz not null default clock_timestamp(),
  recorded_by text not null default session_user,
  check((mode='target_only')=(target_request_id is not null)),
  check((mode='target_only')=(expires_at is not null)),
  foreign key(organization_id,restaurant_id,branch_id) references public.branches(organization_id,restaurant_id,id) on delete restrict
);
create index kitchen_print_containment_policies_scope_idx on public.kitchen_print_containment_policies(organization_id,restaurant_id,branch_id,revision desc);

alter table public.kitchen_print_dispatch_holds enable row level security;
alter table public.kitchen_print_dispatch_holds force row level security;
alter table public.kitchen_print_containment_policies enable row level security;
alter table public.kitchen_print_containment_policies force row level security;
revoke all on public.kitchen_print_dispatch_holds,public.kitchen_print_containment_policies from public,anon,authenticated,service_role;
create policy kitchen_print_dispatch_holds_sel_deny on public.kitchen_print_dispatch_holds for select to authenticated using(false);
create policy kitchen_print_dispatch_holds_ins_deny on public.kitchen_print_dispatch_holds for insert to authenticated with check(false);
create policy kitchen_print_dispatch_holds_upd_deny on public.kitchen_print_dispatch_holds for update to authenticated using(false) with check(false);
create policy kitchen_print_dispatch_holds_del_deny on public.kitchen_print_dispatch_holds for delete to authenticated using(false);
create policy kitchen_print_containment_policies_sel_deny on public.kitchen_print_containment_policies for select to authenticated using(false);
create policy kitchen_print_containment_policies_ins_deny on public.kitchen_print_containment_policies for insert to authenticated with check(false);
create policy kitchen_print_containment_policies_upd_deny on public.kitchen_print_containment_policies for update to authenticated using(false) with check(false);
create policy kitchen_print_containment_policies_del_deny on public.kitchen_print_containment_policies for delete to authenticated using(false);

-- Common serialization fence: writer EXCLUSIVE, pull/target/read SHARED.
-- Acquire it BEFORE hierarchy/session locks, then dispatch row locks. The
-- READ COMMITTED requirement makes each post-wait statement see committed
-- holds; repeatable-read snapshots must never authorize stale automatic work.
create function app.lock_kitchen_print_containment(p_branch_id uuid,p_exclusive boolean)
returns void language plpgsql volatile set search_path='' as $$
begin
  if p_branch_id is null or current_setting('transaction_isolation')<>'read committed' then
    raise exception 'containment requires a branch and read committed isolation' using errcode='25000';
  end if;
  if p_exclusive then
    perform pg_advisory_xact_lock(hashtextextended('kitchen-print-containment:'||p_branch_id::text,0));
  else
    perform pg_advisory_xact_lock_shared(hashtextextended('kitchen-print-containment:'||p_branch_id::text,0));
  end if;
end; $$;
revoke all on function app.lock_kitchen_print_containment(uuid,boolean) from public,anon,authenticated,service_role;

create function app.kitchen_print_containment_audit_guard() returns trigger
language plpgsql volatile set search_path='' as $$
declare v_dispatch public.kitchen_print_dispatches;
begin
  if tg_op<>'INSERT' then
    raise exception 'containment audit history is immutable' using errcode='42501';
  end if;
  perform app.lock_kitchen_print_containment(new.branch_id,true);
  new.recorded_at:=clock_timestamp();
  new.recorded_by:=session_user;
  -- Allocate AFTER the lock: sequence order also orders committed changes in
  -- this branch, even when an insert waited for an earlier operator action.
  new.revision:=nextval('app.kitchen_print_containment_revision');
  if tg_table_name='kitchen_print_dispatch_holds' then
    select * into v_dispatch from public.kitchen_print_dispatches d where d.id=new.dispatch_id for update;
    if not found or row(v_dispatch.organization_id,v_dispatch.restaurant_id,v_dispatch.branch_id)
      is distinct from row(new.organization_id,new.restaurant_id,new.branch_id) then
      raise exception 'hold dispatch scope mismatch' using errcode='23514';
    end if;
    if md5(to_jsonb(v_dispatch)::text) is distinct from new.dispatch_fingerprint
      or new.snapshot_at>new.recorded_at then
      raise exception 'hold snapshot changed; reconcile exact manifest' using errcode='23514';
    end if;
    if exists(select 1 from public.web_order_print_attempts a where a.dispatch_id=new.dispatch_id) then
      raise exception 'target-enrolled dispatch cannot be a legacy hold' using errcode='23514';
    end if;
  elsif new.mode='target_only' and (new.expires_at<=new.recorded_at
    or new.expires_at>new.recorded_at+interval '1 hour') then
    raise exception 'target-only policy requires a short future expiry' using errcode='23514';
  end if;
  return new;
end; $$;
revoke all on function app.kitchen_print_containment_audit_guard() from public,anon,authenticated,service_role;
create trigger kitchen_print_dispatch_holds_guard before insert or update or delete on public.kitchen_print_dispatch_holds
  for each row execute function app.kitchen_print_containment_audit_guard();
create trigger kitchen_print_dispatch_holds_no_truncate before truncate on public.kitchen_print_dispatch_holds
  for each statement execute function app.kitchen_print_containment_audit_guard();
create trigger kitchen_print_containment_policies_guard before insert or update or delete on public.kitchen_print_containment_policies
  for each row execute function app.kitchen_print_containment_audit_guard();
create trigger kitchen_print_containment_policies_no_truncate before truncate on public.kitchen_print_containment_policies
  for each statement execute function app.kitchen_print_containment_audit_guard();

create function app.kitchen_print_containment_state(p_org uuid,p_rest uuid,p_branch uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_policy public.kitchen_print_containment_policies; v_revision bigint; v_held jsonb;
begin
  select * into v_policy from public.kitchen_print_containment_policies p
    where p.organization_id=p_org and p.restaurant_id=p_rest and p.branch_id=p_branch order by revision desc limit 1;
  select coalesce(jsonb_agg(h.dispatch_id order by h.dispatch_id),'[]'::jsonb),coalesce(max(h.revision),0)
    into v_held,v_revision from public.kitchen_print_dispatch_holds h
    where h.organization_id=p_org and h.restaurant_id=p_rest and h.branch_id=p_branch;
  return jsonb_build_object('mode',case when v_policy.mode='target_only' and v_policy.expires_at<=clock_timestamp()
    then 'blocked' else coalesce(v_policy.mode,'ordinary') end,
    'target_request_id',v_policy.target_request_id,'expires_at',v_policy.expires_at,
    'revision',greatest(v_revision,coalesce(v_policy.revision,0)),'held_dispatch_ids',v_held);
end; $$;
revoke all on function app.kitchen_print_containment_state(uuid,uuid,uuid) from public,anon,authenticated,service_role;

-- Real paired POS proof, scoped on the server; no caller-selected tenant or
-- branch and no hold/policy mutation endpoint. Session renewal remains the
-- existing authentication authority after the containment lock.
create function app.pos_kitchen_print_containment(p_device_id uuid,p_session_token text)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_branch uuid; v_proof jsonb;
begin
  if auth.uid() is null or p_device_id is null or p_session_token is null
    or length(p_session_token)>4096 or btrim(p_session_token)='' then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  select ds.branch_id into v_branch from public.device_sessions ds
    where ds.device_id=p_device_id and ds.session_token_ref=app.hash_provisioning_secret(btrim(p_session_token))
      and ds.is_active and ds.revoked_at is null and (ds.expires_at is null or ds.expires_at>clock_timestamp());
  if v_branch is null then return jsonb_build_object('ok',false,'error','invalid_session'); end if;
  perform app.lock_kitchen_print_containment(v_branch,false);
  v_proof:=app.renew_device_session(p_device_id,p_session_token);
  if v_proof->>'ok' is distinct from 'true' or v_proof->>'device_type' is distinct from 'pos'
    or (v_proof->>'branch_id')::uuid is distinct from v_branch then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  return jsonb_build_object('ok',true,'device_id',p_device_id,
    'organization_id',v_proof->>'organization_id','restaurant_id',v_proof->>'restaurant_id','branch_id',v_branch)
    ||app.kitchen_print_containment_state((v_proof->>'organization_id')::uuid,(v_proof->>'restaurant_id')::uuid,v_branch);
end; $$;
revoke all on function app.pos_kitchen_print_containment(uuid,text) from public,anon,authenticated,service_role;
grant execute on function app.pos_kitchen_print_containment(uuid,text) to authenticated;
create function public.pos_kitchen_print_containment(p_device_id uuid,p_session_token text)
returns jsonb language sql volatile security invoker set search_path='' as $$
  select app.pos_kitchen_print_containment(p_device_id,p_session_token);
$$;
revoke all on function public.pos_kitchen_print_containment(uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.pos_kitchen_print_containment(uuid,text) to authenticated;


-- Existing target fence retained; only scoped admission checks are added.
create or replace function app.pos_web_order_print_operation(
  p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,p_request_id uuid,
  p_action text,p_attempt_id uuid default null,p_client_status text default null,p_error_code text default null
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare
  v_context jsonb;
  v_target public.web_order_print_attempts;
  v_dispatch public.kitchen_print_dispatches;
  v_now timestamptz;
  v_mode text;
  v_revision integer;
  v_readiness public.kitchen_printer_readiness_reports;
  v_result jsonb;
  v_state text;
  v_policy jsonb;
  v_scope_branch uuid;
begin
  -- Resolve the session scope without locking, then take the common branch
  -- fence BEFORE the unchanged context/hierarchy/request/dispatch lock order.
  select ds.branch_id into v_scope_branch from public.device_sessions ds
    where ds.device_id=p_device_id and ds.session_token_ref=app.hash_provisioning_secret(btrim(p_device_session_token))
      and ds.is_active and ds.revoked_at is null and (ds.expires_at is null or ds.expires_at>clock_timestamp());
  if v_scope_branch is not null then perform app.lock_kitchen_print_containment(v_scope_branch,false); end if;
  v_context:=app.pos_web_order_context(p_pin_session_id,p_device_id,p_device_session_token);
  if v_context->>'ok' is distinct from 'true' then
    return jsonb_build_object('ok',false,'error',v_context->>'error');
  end if;
  if (v_context->>'branch_id')::uuid is distinct from v_scope_branch then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  if p_request_id is null or p_action not in ('claim','begin','finish','status')
    or p_action is null or (p_action in ('begin','finish') and p_attempt_id is null)
    or (p_action='finish' and (p_client_status is null or p_client_status not in
      ('transport_accepted','possibly_printed','failed_retryable','blocked_configuration')))
    or (p_error_code is not null and p_error_code !~ '^[a-z0-9_.\-]{1,64}$') then
    return jsonb_build_object('ok',false,'error','invalid_request');
  end if;
  -- Lock order is the established hierarchy/PIN context, request, private
  -- target, dispatch. Caller supplies no order/dispatch/branch authority.
  perform 1 from public.web_order_requests w
    join public.web_order_decisions wd on wd.request_id=w.id
      and wd.organization_id=w.organization_id and wd.restaurant_id=w.restaurant_id
      and wd.branch_id=w.branch_id and wd.canonical_order_id=w.canonical_order_id
    where w.id=p_request_id and w.organization_id=(v_context->>'organization_id')::uuid
      and w.restaurant_id=(v_context->>'restaurant_id')::uuid
      and w.branch_id=(v_context->>'branch_id')::uuid
      and w.status='accepted' and wd.decision='accepted' for share of w;
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
  select * into v_target from public.web_order_print_attempts a
    where a.request_id=p_request_id and a.organization_id=(v_context->>'organization_id')::uuid
      and a.restaurant_id=(v_context->>'restaurant_id')::uuid
      and a.branch_id=(v_context->>'branch_id')::uuid for update;
  if not found then return jsonb_build_object('ok',false,'error','target_unavailable'); end if;
  select * into v_dispatch from public.kitchen_print_dispatches d
    where d.id=v_target.dispatch_id and d.organization_id=v_target.organization_id
      and d.restaurant_id=v_target.restaurant_id and d.branch_id=v_target.branch_id
      and d.order_id=v_target.canonical_order_id and d.dispatch_type='initial_order'
      and d.service_round_id is null for update;
  if not found then return jsonb_build_object('ok',false,'error','target_unavailable'); end if;
  v_now:=clock_timestamp();
  if (v_context->>'pin_expires_at')::timestamptz<=v_now
    or (v_context->>'session_expires_at')::timestamptz<=v_now then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  v_result:=jsonb_build_object('ok',true,'request_id',p_request_id,
    'canonical_order_id',v_target.canonical_order_id,'decision_id',v_target.decision_id,
    'dispatch_id',v_target.dispatch_id,'attempt_id',v_target.attempt_id,
    'printer_assignment_id',v_target.printer_assignment_id,'send_authorized',false);
  v_state:=case when v_target.outcome='transport_accepted' then 'transport_accepted'
    when v_target.attempt_id is not null then 'reconciliation_required'
    when v_dispatch.superseded_by_dispatch_id is not null then 'superseded'
    when v_target.claim_expires_at>v_now then 'claimed' else 'available' end;
  if p_action='status' then return v_result||jsonb_build_object('state',v_state); end if;
  if p_action='finish' then
    if v_target.attempt_id is distinct from p_attempt_id
      or v_target.attempt_device_id is distinct from p_device_id
      or v_target.attempt_pin_session_id is distinct from p_pin_session_id then
      return jsonb_build_object('ok',false,'error','not_attempt_owner');
    end if;
    if v_target.finished_at is not null then
      if v_target.outcome is distinct from p_client_status or v_target.error_code is distinct from p_error_code then
        return jsonb_build_object('ok',false,'error','outcome_conflict');
      end if;
      return v_result||jsonb_build_object('state',v_state,'replayed',true);
    end if;
    update public.web_order_print_attempts set outcome=p_client_status,error_code=p_error_code,
      finished_at=v_now where request_id=p_request_id;
    -- A failed native send after reservation is also permanently fenced. It
    -- may have sent zero bytes, but this contract never infers safe retransmit.
    update public.kitchen_print_dispatches set
      last_client_status=case when p_client_status='transport_accepted' then 'transport_accepted' else 'possibly_printed' end,
      last_error_code=p_error_code,
      completed_at=case when p_client_status='transport_accepted' then v_now else completed_at end,
      claim_expires_at=null,updated_at=v_now where id=v_target.dispatch_id;
    return v_result||jsonb_build_object('state',case when p_client_status='transport_accepted'
      then 'transport_accepted' else 'reconciliation_required' end,'replayed',false);
  end if;
  if v_target.attempt_id is not null then return v_result||jsonb_build_object('state',v_state); end if;
  if v_dispatch.superseded_by_dispatch_id is not null or v_dispatch.completed_at is not null
    or v_dispatch.last_client_status='possibly_printed' then
    return v_result||jsonb_build_object('state','reconciliation_required');
  end if;
  v_policy:=app.kitchen_print_containment_state(v_target.organization_id,v_target.restaurant_id,v_target.branch_id);
  if v_policy->>'mode'='blocked' or (v_policy->>'mode'='target_only'
    and (v_policy->>'target_request_id')::uuid is distinct from p_request_id)
    or exists(select 1 from public.kitchen_print_dispatch_holds h where h.dispatch_id=v_target.dispatch_id) then
    return jsonb_build_object('ok',false,'error','containment_blocked');
  end if;
  select b.kitchen_workflow_mode,b.kitchen_workflow_mode_revision into v_mode,v_revision
    from public.branches b where b.id=v_target.branch_id
      and b.organization_id=v_target.organization_id and b.restaurant_id=v_target.restaurant_id;
  if v_mode is distinct from 'printer_only' then
    return jsonb_build_object('ok',false,'error','branch_not_printer_only');
  end if;
  perform 1 from public.shifts s where s.organization_id=v_target.organization_id
    and s.restaurant_id=v_target.restaurant_id and s.branch_id=v_target.branch_id
    and s.device_id=p_device_id and s.status='open' and s.deleted_at is null for share;
  if not found then return jsonb_build_object('ok',false,'error','shift_required'); end if;
  select * into v_readiness from public.kitchen_printer_readiness_reports rr
    where rr.organization_id=v_target.organization_id and rr.restaurant_id=v_target.restaurant_id
      and rr.branch_id=v_target.branch_id and rr.device_id=p_device_id
      and rr.expires_at>clock_timestamp() and app.kitchen_readiness_report_qualifies(rr,v_revision)
    for share;
  if not found then return jsonb_build_object('ok',false,'error','readiness_required'); end if;
  -- Block assignment mutation until this reservation/claim commits, then
  -- recheck qualification and deadlines after the final possibly-blocking lock.
  perform 1 from public.printer_devices pd where pd.id=v_readiness.printer_assignment_id
    and pd.organization_id=v_target.organization_id and pd.restaurant_id=v_target.restaurant_id
    and pd.branch_id=v_target.branch_id for share;
  v_now:=clock_timestamp();
  if not app.kitchen_readiness_report_qualifies(v_readiness,v_revision)
    or v_readiness.expires_at<=v_now then
    return jsonb_build_object('ok',false,'error','readiness_required');
  end if;
  if (v_context->>'pin_expires_at')::timestamptz<=v_now
    or (v_context->>'session_expires_at')::timestamptz<=v_now then
    return jsonb_build_object('ok',false,'error','invalid_session');
  end if;
  v_policy:=app.kitchen_print_containment_state(v_target.organization_id,v_target.restaurant_id,v_target.branch_id);
  if v_policy->>'mode'='blocked' or (v_policy->>'mode'='target_only'
    and (v_policy->>'target_request_id')::uuid is distinct from p_request_id) then
    return jsonb_build_object('ok',false,'error','containment_blocked');
  end if;
  if p_action='begin' then
    if v_target.claimed_by_device_id is distinct from p_device_id
      or v_target.claim_expires_at<=v_now or v_target.claim_expires_at is null
      or v_target.printer_assignment_id is distinct from v_readiness.printer_assignment_id
      or v_dispatch.claimed_by_device_id is distinct from p_device_id then
      return jsonb_build_object('ok',false,'error','not_claim_owner');
    end if;
    update public.web_order_print_attempts set attempt_id=p_attempt_id,attempt_device_id=p_device_id,
      attempt_pin_session_id=p_pin_session_id,attempt_reserved_at=v_now where request_id=p_request_id;
    return v_result||jsonb_build_object('state','send_reserved','send_authorized',true,
      'attempt_id',p_attempt_id,'printer_assignment_id',v_target.printer_assignment_id);
  end if;
  if v_target.claimed_by_device_id is not null and v_target.claimed_by_device_id<>p_device_id
    and v_target.claim_expires_at>v_now then
    return v_result||jsonb_build_object('state','busy');
  end if;
  update public.web_order_print_attempts set claimed_by_device_id=p_device_id,
    claim_expires_at=v_now+interval '2 minutes',printer_assignment_id=v_readiness.printer_assignment_id
    where request_id=p_request_id;
  update public.kitchen_print_dispatches set claimed_at=v_now,claimed_by_device_id=p_device_id,
    claim_expires_at=v_now+interval '2 minutes',updated_at=v_now where id=v_target.dispatch_id;
  return v_result||jsonb_build_object('state','claimed','printer_assignment_id',v_readiness.printer_assignment_id,
    'dispatch',jsonb_build_object('id',v_dispatch.id,'dispatch_type',v_dispatch.dispatch_type,
      'order_id',v_dispatch.order_id,'service_round_id',v_dispatch.service_round_id,
      'payload_version',v_dispatch.payload_version,'payload',v_dispatch.money_free_payload,
      'created_at',v_dispatch.created_at,'claim_expires_at',v_now+interval '2 minutes'));
end; $$;
revoke all on function app.pos_web_order_print_operation(uuid,uuid,text,uuid,text,uuid,text,text)
  from public,anon,authenticated,service_role;


-- Existing broad tuple/default/page contract retained with containment.
create or replace function app.pull_kitchen_print_dispatches(
  p_device_id         uuid,
  p_session_token     text,
  p_limit             integer default 20,
  p_cursor_created_at timestamptz default null,
  p_cursor_id         uuid default null,
  -- CORRECTION-001: the cursor carries the FULL ordering tuple. No 001C
  -- client exists yet, so adding the component is a safe contract change;
  -- it is LAST with a default, so cursorless recovery calls are unchanged.
  p_cursor_type_rank  integer default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_hash      text;
  v_org       uuid;
  v_rest      uuid;
  v_branch    uuid;
  v_dtype     text;
  v_mode      text;
  v_brev      integer;
  v_limit     integer;
  v_rows      jsonb;
  v_count     integer;
  v_last_at   timestamptz;
  v_last_rank integer;
  v_last_id   uuid;
  v_has_more  boolean;
  v_policy    jsonb;
begin
  if p_device_id is null or p_session_token is null or btrim(p_session_token) = '' then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_print_dispatches');
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 50 then
    return jsonb_build_object('ok', false, 'error', 'invalid_limit', 'entity', 'kitchen_print_dispatches');
  end if;
  -- CORRECTION-001: the cursor is ALL-OR-NOTHING across its three components
  -- and the rank must be a real rank; a malformed cursor is rejected, never
  -- guessed around.
  if not ((p_cursor_created_at is null and p_cursor_id is null and p_cursor_type_rank is null)
          or (p_cursor_created_at is not null and p_cursor_id is not null and p_cursor_type_rank is not null)) then
    return jsonb_build_object('ok', false, 'error', 'invalid_cursor', 'entity', 'kitchen_print_dispatches');
  end if;
  if p_cursor_type_rank is not null and p_cursor_type_rank not in (0, 1, 2) then
    return jsonb_build_object('ok', false, 'error', 'invalid_cursor', 'entity', 'kitchen_print_dispatches');
  end if;
  v_hash := app.hash_provisioning_secret(btrim(p_session_token));

  select ds.organization_id, ds.restaurant_id, ds.branch_id, d.device_type
    into v_org, v_rest, v_branch, v_dtype
    from public.device_sessions ds
    join public.device_pairings dp on dp.id = ds.device_pairing_id
      and dp.organization_id = ds.organization_id
      and dp.restaurant_id   = ds.restaurant_id
      and dp.branch_id       = ds.branch_id
      and dp.device_id       = ds.device_id
    join public.devices d on d.id = ds.device_id
      and d.organization_id = ds.organization_id
    join public.branches b on b.organization_id = ds.organization_id
      and b.restaurant_id = ds.restaurant_id and b.id = ds.branch_id
      and b.deleted_at is null and b.status = 'active'
    join public.restaurants r on r.organization_id = ds.organization_id
      and r.id = ds.restaurant_id and r.deleted_at is null and r.status = 'active'
    join public.organizations org on org.id = ds.organization_id
      and org.deleted_at is null and org.status = 'active'
    where ds.device_id = p_device_id
      and ds.session_token_ref = v_hash
      and ds.is_active and ds.revoked_at is null
      and (ds.expires_at is null or ds.expires_at > now())
      and dp.status = 'active' and dp.revoked_at is null and dp.deleted_at is null
      and d.is_active and d.deleted_at is null;
  if v_org is null then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_print_dispatches');
  end if;
  if v_dtype <> 'pos' then
    -- KDS is explicitly denied: printer-only dispatch payloads never reach a
    -- KDS client through any channel.
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_print_dispatches');
  end if;

  -- Acquire before renewal hierarchy locks. A hold writer that won this
  -- fence commits before every candidate/page/has_more post-lock statement.
  perform app.lock_kitchen_print_containment(v_branch,false);
  v_policy:=app.kitchen_print_containment_state(v_org,v_rest,v_branch);
  if v_policy->>'mode'<>'ordinary' then
    return jsonb_build_object('ok',false,'error','containment_blocked','entity','kitchen_print_dispatches');
  end if;

  -- BIZBOT-DEVICE-SESSION-FIX-001: renew only after this RPC proves its device role.
  if not (app.renew_device_session(p_device_id, p_session_token) ->> 'ok')::boolean then
    return jsonb_build_object('ok', false, 'error', 'invalid_session', 'entity', 'kitchen_print_dispatches');
  end if;

  select b.kitchen_workflow_mode, b.kitchen_workflow_mode_revision
    into v_mode, v_brev
    from public.branches b
    where b.id = v_branch and b.organization_id = v_org and b.deleted_at is null;
  if coalesce(v_mode, 'kds') <> 'printer_only' then
    return jsonb_build_object('ok', false, 'error', 'branch_not_printer_only', 'entity', 'kitchen_print_dispatches');
  end if;

  -- The deploy-ahead compatibility guard: only a device with a FRESH,
  -- activation-capable readiness report may claim. No deployed client reports
  -- the capability, so production claims are impossible today.
  -- CORRECTION-001: the report must also carry the CURRENT branch mode
  -- revision — a device whose cached mode view is stale may not claim.
  if not exists (
    select 1 from public.kitchen_printer_readiness_reports rr
    where rr.organization_id = v_org
      and rr.device_id = p_device_id
      and rr.branch_id = v_branch
      and rr.expires_at > now()
      -- KITCHEN-MODE-001C3B1A: the qualifying predicate now REQUIRES a stable,
      -- still-valid kitchen printer assignment. A NULL-assignment 001C3A
      -- report can never unlock the claim. Centralized in the helper so every
      -- consumer stays in exact sync.
      and app.kitchen_readiness_report_qualifies(rr, v_brev)
  ) then
    return jsonb_build_object('ok', false, 'error', 'readiness_required', 'entity', 'kitchen_print_dispatches');
  end if;

  v_limit := p_limit;

  -- ATOMIC CLAIM (CORRECTION-001 tuple contract): ORDER BY and the keyset
  -- cursor use the SAME stable tuple (created_at, type_rank, id), so tied
  -- timestamps can never skip or duplicate a row across a drain loop. The
  -- inner FOR UPDATE serializes concurrent pullers; the outer WHERE re-proves
  -- claimability AFTER the lock wait, so two devices can never claim the
  -- same row. Stale claims (expired) and this device's own claims are
  -- reclaimable; possibly_printed rows are NEVER served; superseded rows are
  -- gone from this feed forever; an UNRESOLVED row never ages out — there is
  -- deliberately NO time window here (CORRECTION-001 retention contract).
  with candidates as (
    select d.id
      from public.kitchen_print_dispatches d
      where d.organization_id = v_org
        and d.branch_id = v_branch
        and d.completed_at is null
        and d.superseded_by_dispatch_id is null
        and d.last_client_status is distinct from 'possibly_printed'
        -- New accepted web initial tickets are served only by the fenced target RPC.
        and not exists (select 1 from public.web_order_print_attempts wa where wa.dispatch_id=d.id)
        and not exists (select 1 from public.kitchen_print_dispatch_holds h where h.dispatch_id=d.id)
        and (d.claimed_at is null
             or d.claim_expires_at < now()
             or d.claimed_by_device_id = p_device_id)
        and (p_cursor_created_at is null
             or (d.created_at,
                 case d.dispatch_type when 'initial_order' then 0
                                      when 'service_round' then 1 else 2 end,
                 d.id)
                > (p_cursor_created_at, p_cursor_type_rank, p_cursor_id))
      order by d.created_at,
               case d.dispatch_type when 'initial_order' then 0
                                    when 'service_round' then 1 else 2 end,
               d.id
      limit v_limit
      for update of d
  )
  update public.kitchen_print_dispatches d
    set claimed_at = now(),
        claimed_by_device_id = p_device_id,
        claim_expires_at = now() + interval '10 minutes',
        updated_at = now()
    from candidates c
    where d.id = c.id
      and d.completed_at is null
      and d.superseded_by_dispatch_id is null
      and d.last_client_status is distinct from 'possibly_printed'
      -- Re-prove containment and target exclusion AFTER dispatch row locks.
      and not exists (select 1 from public.kitchen_print_dispatch_holds h where h.dispatch_id=d.id)
      and not exists (select 1 from public.web_order_print_attempts wa where wa.dispatch_id=d.id)
      and (d.claimed_at is null
           or d.claim_expires_at < now()
           or d.claimed_by_device_id = p_device_id);

  -- The returned page: this device's LIVE claims in tuple order, HARD-capped
  -- at p_limit — own pre-existing active claims can never inflate the page
  -- beyond the requested limit (CORRECTION-001).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', p.id,
           'dispatch_type', p.dispatch_type,
           'order_id', p.order_id,
           'service_round_id', p.service_round_id,
           'payload_version', p.payload_version,
           'payload', p.money_free_payload,
           'created_at', p.created_at,
           'claim_expires_at', p.claim_expires_at)
         order by p.created_at, p.type_rank, p.id), '[]'::jsonb),
         count(*)::int,
         (array_agg(p.created_at order by p.created_at desc, p.type_rank desc, p.id desc))[1],
         (array_agg(p.type_rank  order by p.created_at desc, p.type_rank desc, p.id desc))[1],
         (array_agg(p.id         order by p.created_at desc, p.type_rank desc, p.id desc))[1]
    into v_rows, v_count, v_last_at, v_last_rank, v_last_id
    from (
      select d.*,
             case d.dispatch_type when 'initial_order' then 0
                                  when 'service_round' then 1 else 2 end as type_rank
        from public.kitchen_print_dispatches d
        where d.organization_id = v_org
          and d.branch_id = v_branch
          and d.claimed_by_device_id = p_device_id
          and d.claim_expires_at > now()
          and d.completed_at is null
          and d.superseded_by_dispatch_id is null
          and d.last_client_status is distinct from 'possibly_printed'
        -- New accepted web initial tickets are served only by the fenced target RPC.
        and not exists (select 1 from public.web_order_print_attempts wa where wa.dispatch_id=d.id)
        and not exists (select 1 from public.kitchen_print_dispatch_holds h where h.dispatch_id=d.id)
          and (p_cursor_created_at is null
               or (d.created_at,
                   case d.dispatch_type when 'initial_order' then 0
                                        when 'service_round' then 1 else 2 end,
                   d.id)
                  > (p_cursor_created_at, p_cursor_type_rank, p_cursor_id))
        order by d.created_at,
                 case d.dispatch_type when 'initial_order' then 0
                                      when 'service_round' then 1 else 2 end,
                 d.id
        limit v_limit
    ) p;

  -- TRUTHFUL has_more (CORRECTION-001): true iff a row SERVABLE TO THIS
  -- DEVICE (its own live claim, or still claimable by anyone) exists beyond
  -- the returned page's last tuple.
  if v_count = 0 then
    v_has_more := false;
  else
    select exists (
      select 1 from public.kitchen_print_dispatches d
      where d.organization_id = v_org
        and d.branch_id = v_branch
        and d.completed_at is null
        and d.superseded_by_dispatch_id is null
        and d.last_client_status is distinct from 'possibly_printed'
        -- New accepted web initial tickets are served only by the fenced target RPC.
        and not exists (select 1 from public.web_order_print_attempts wa where wa.dispatch_id=d.id)
        and not exists (select 1 from public.kitchen_print_dispatch_holds h where h.dispatch_id=d.id)
        and ((d.claimed_by_device_id = p_device_id and d.claim_expires_at > now())
             or d.claimed_at is null
             or d.claim_expires_at < now())
        and (d.created_at,
             case d.dispatch_type when 'initial_order' then 0
                                  when 'service_round' then 1 else 2 end,
             d.id) > (v_last_at, v_last_rank, v_last_id))
      into v_has_more;
  end if;

  return jsonb_build_object(
    'ok', true, 'entity', 'kitchen_print_dispatches',
    'dispatches', v_rows,
    'has_more', v_has_more,
    'next_cursor', case when v_count > 0
                        then jsonb_build_object('created_at', v_last_at, 'type_rank', v_last_rank, 'id', v_last_id)
                        else null end,
    'server_ts', now());
end;
$$;


commit;
