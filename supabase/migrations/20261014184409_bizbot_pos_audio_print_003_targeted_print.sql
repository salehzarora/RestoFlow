-- BIZBOT-POS-AUDIO-PRINT-003: future accepted web orders only. No backfill.
-- A reservation is not proof of paper: a crash after reservation requires
-- operator reconciliation, even when physical transmission never started.
begin;

create table public.web_order_print_attempts (
  request_id uuid primary key references public.web_order_decisions(request_id) on delete restrict,
  organization_id uuid not null,
  restaurant_id uuid not null,
  branch_id uuid not null,
  canonical_order_id uuid not null,
  decision_id uuid not null,
  dispatch_id uuid not null unique,
  created_at timestamptz not null default clock_timestamp(),
  claimed_by_device_id uuid,
  claim_expires_at timestamptz,
  printer_assignment_id uuid,
  attempt_id uuid unique,
  attempt_device_id uuid,
  attempt_pin_session_id uuid,
  attempt_reserved_at timestamptz,
  outcome text check (outcome in ('transport_accepted','possibly_printed','failed_retryable','blocked_configuration')),
  error_code text check (error_code ~ '^[a-z0-9_.\-]{1,64}$'),
  finished_at timestamptz,
  foreign key (organization_id,restaurant_id,branch_id,request_id)
    references public.web_order_requests(organization_id,restaurant_id,branch_id,id) on delete restrict,
  foreign key (organization_id,restaurant_id,branch_id,decision_id)
    references public.web_order_decisions(organization_id,restaurant_id,branch_id,decision_id) on delete restrict,
  foreign key (organization_id,canonical_order_id,dispatch_id)
    references public.kitchen_print_dispatches(organization_id,order_id,id) on delete restrict,
  foreign key (organization_id,restaurant_id,branch_id,claimed_by_device_id)
    references public.devices(organization_id,restaurant_id,branch_id,id) on delete restrict,
  foreign key (organization_id,restaurant_id,branch_id,attempt_device_id)
    references public.devices(organization_id,restaurant_id,branch_id,id) on delete restrict,
  foreign key (organization_id,restaurant_id,branch_id,attempt_pin_session_id)
    references public.pin_sessions(organization_id,restaurant_id,branch_id,id) on delete restrict,
  foreign key (organization_id,restaurant_id,branch_id,printer_assignment_id)
    references public.printer_devices(organization_id,restaurant_id,branch_id,id) on delete restrict,
  check ((claimed_by_device_id is null) = (claim_expires_at is null)),
  check ((attempt_id is null) = (attempt_reserved_at is null)),
  check ((attempt_id is null) = (attempt_device_id is null)),
  check ((attempt_id is null) = (attempt_pin_session_id is null)),
  check ((outcome is null) = (finished_at is null)),
  check (outcome is null or attempt_id is not null)
);
alter table public.web_order_print_attempts enable row level security;
alter table public.web_order_print_attempts force row level security;
revoke all on public.web_order_print_attempts from public,anon,authenticated,service_role;
create policy web_order_print_attempts_sel_deny on public.web_order_print_attempts for select to authenticated using(false);
create policy web_order_print_attempts_ins_deny on public.web_order_print_attempts for insert to authenticated with check(false);
create policy web_order_print_attempts_upd_deny on public.web_order_print_attempts for update to authenticated using(false) with check(false);
create policy web_order_print_attempts_del_deny on public.web_order_print_attempts for delete to authenticated using(false);
comment on table public.web_order_print_attempts is
  'BIZBOT-POS-AUDIO-PRINT-003: private exact-target automatic transmission fence. New accepted printer-only web decisions only; no historical backfill. attempt_reserved_at is irreversible, including a lost begin reply or a crash before physical send. Terminal outcomes are transport observations, NEVER proof of paper.';

create function app.web_order_print_attempt_guard() returns trigger
language plpgsql set search_path='' as $$
begin
  if tg_op in ('DELETE','TRUNCATE') then
    raise exception 'web order print attempt history is immutable' using errcode='42501';
  end if;
  if row(new.request_id,new.organization_id,new.restaurant_id,new.branch_id,
    new.canonical_order_id,new.decision_id,new.dispatch_id,new.created_at)
    is distinct from row(old.request_id,old.organization_id,old.restaurant_id,old.branch_id,
    old.canonical_order_id,old.decision_id,old.dispatch_id,old.created_at) then
    raise exception 'web order print identity is immutable' using errcode='42501';
  end if;
  if old.attempt_id is not null and row(new.attempt_id,new.attempt_device_id,
    new.attempt_pin_session_id,new.attempt_reserved_at,new.claimed_by_device_id,
    new.claim_expires_at,new.printer_assignment_id) is distinct from
    row(old.attempt_id,old.attempt_device_id,old.attempt_pin_session_id,
    old.attempt_reserved_at,old.claimed_by_device_id,old.claim_expires_at,old.printer_assignment_id) then
    raise exception 'web order send reservation is irreversible' using errcode='42501';
  end if;
  if old.finished_at is not null and row(new.outcome,new.error_code,new.finished_at)
    is distinct from row(old.outcome,old.error_code,old.finished_at) then
    raise exception 'web order print outcome is immutable' using errcode='42501';
  end if;
  return new;
end; $$;
revoke all on function app.web_order_print_attempt_guard() from public,anon,authenticated,service_role;
create trigger web_order_print_attempts_guard before update or delete
  on public.web_order_print_attempts for each row execute function app.web_order_print_attempt_guard();
create trigger web_order_print_attempts_no_truncate before truncate
  on public.web_order_print_attempts for each statement execute function app.web_order_print_attempt_guard();

-- The initial dispatch already exists inside the unchanged order.submit
-- transaction when the trusted accepted decision is inserted. Seed the hold
-- before commit: a broad pull can see neither row, or both, never dispatch alone.
create function app.reserve_accepted_web_order_print() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if new.decision='accepted' then
    insert into public.web_order_print_attempts(request_id,organization_id,restaurant_id,
      branch_id,canonical_order_id,decision_id,dispatch_id)
    select new.request_id,new.organization_id,new.restaurant_id,new.branch_id,
      new.canonical_order_id,new.decision_id,d.id
    from public.kitchen_print_dispatches d
    join public.branches b on b.organization_id=new.organization_id
      and b.restaurant_id=new.restaurant_id and b.id=new.branch_id
    where d.organization_id=new.organization_id and d.restaurant_id=new.restaurant_id
      and d.branch_id=new.branch_id and d.order_id=new.canonical_order_id
      and d.dispatch_type='initial_order' and d.service_round_id is null
      and d.idempotency_key='initial:'||new.canonical_order_id::text
      and b.kitchen_workflow_mode='printer_only';
  end if;
  return new;
end; $$;
revoke all on function app.reserve_accepted_web_order_print() from public,anon,authenticated,service_role;
create trigger web_order_decisions_reserve_print after insert on public.web_order_decisions
  for each row execute function app.reserve_accepted_web_order_print();

create function app.pos_web_order_print_operation(
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
begin
  v_context:=app.pos_web_order_context(p_pin_session_id,p_device_id,p_device_session_token);
  if v_context->>'ok' is distinct from 'true' then
    return jsonb_build_object('ok',false,'error',v_context->>'error');
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

create function app.pos_claim_web_order_print(p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,p_request_id uuid)
returns jsonb language sql volatile security definer set search_path='' as $$
  select app.pos_web_order_print_operation(p_pin_session_id,p_device_id,p_device_session_token,p_request_id,'claim');
$$;
create function app.pos_begin_web_order_print(p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,p_request_id uuid,p_attempt_id uuid)
returns jsonb language sql volatile security definer set search_path='' as $$
  select app.pos_web_order_print_operation(p_pin_session_id,p_device_id,p_device_session_token,p_request_id,'begin',p_attempt_id);
$$;
create function app.pos_finish_web_order_print(p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,p_request_id uuid,p_attempt_id uuid,p_client_status text,p_error_code text default null)
returns jsonb language sql volatile security definer set search_path='' as $$
  select app.pos_web_order_print_operation(p_pin_session_id,p_device_id,p_device_session_token,p_request_id,'finish',p_attempt_id,p_client_status,p_error_code);
$$;
create function app.pos_web_order_print_status(p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,p_request_id uuid)
returns jsonb language sql volatile security definer set search_path='' as $$
  select app.pos_web_order_print_operation(p_pin_session_id,p_device_id,p_device_session_token,p_request_id,'status');
$$;
create function public.pos_claim_web_order_print(p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,p_request_id uuid)
returns jsonb language sql volatile security invoker set search_path='' as $$
  select app.pos_claim_web_order_print(p_pin_session_id,p_device_id,p_device_session_token,p_request_id);
$$;
create function public.pos_begin_web_order_print(p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,p_request_id uuid,p_attempt_id uuid)
returns jsonb language sql volatile security invoker set search_path='' as $$
  select app.pos_begin_web_order_print(p_pin_session_id,p_device_id,p_device_session_token,p_request_id,p_attempt_id);
$$;
create function public.pos_finish_web_order_print(p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,p_request_id uuid,p_attempt_id uuid,p_client_status text,p_error_code text default null)
returns jsonb language sql volatile security invoker set search_path='' as $$
  select app.pos_finish_web_order_print(p_pin_session_id,p_device_id,p_device_session_token,p_request_id,p_attempt_id,p_client_status,p_error_code);
$$;
create function public.pos_web_order_print_status(p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,p_request_id uuid)
returns jsonb language sql volatile security invoker set search_path='' as $$
  select app.pos_web_order_print_status(p_pin_session_id,p_device_id,p_device_session_token,p_request_id);
$$;
revoke all on function public.pos_claim_web_order_print(uuid,uuid,text,uuid),
  public.pos_begin_web_order_print(uuid,uuid,text,uuid,uuid),
  public.pos_finish_web_order_print(uuid,uuid,text,uuid,uuid,text,text),
  public.pos_web_order_print_status(uuid,uuid,text,uuid) from public,anon,authenticated,service_role;
grant execute on function public.pos_claim_web_order_print(uuid,uuid,text,uuid),
  public.pos_begin_web_order_print(uuid,uuid,text,uuid,uuid),
  public.pos_finish_web_order_print(uuid,uuid,text,uuid,uuid,text,text),
  public.pos_web_order_print_status(uuid,uuid,text,uuid) to authenticated;

revoke all on function app.pos_claim_web_order_print(uuid,uuid,text,uuid),
  app.pos_begin_web_order_print(uuid,uuid,text,uuid,uuid),
  app.pos_finish_web_order_print(uuid,uuid,text,uuid,uuid,text,text),
  app.pos_web_order_print_status(uuid,uuid,text,uuid) from public,anon,authenticated,service_role;
grant execute on function app.pos_claim_web_order_print(uuid,uuid,text,uuid),
  app.pos_begin_web_order_print(uuid,uuid,text,uuid,uuid),
  app.pos_finish_web_order_print(uuid,uuid,text,uuid,uuid,text,text),
  app.pos_web_order_print_status(uuid,uuid,text,uuid) to authenticated;


-- Existing pull contract is byte-faithful except for the three target exclusions.
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
