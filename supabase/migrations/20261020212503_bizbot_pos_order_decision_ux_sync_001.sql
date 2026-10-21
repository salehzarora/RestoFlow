-- BIZBOT-POS-ORDER-DECISION-UX-SYNC-001: explicit future customer reason only.
-- No historical backfill, notification activation, canonical or print rewrite.
begin;

create table app.web_order_customer_rejection_reasons (
  request_id uuid primary key references public.web_order_decisions(request_id) on delete restrict,
  organization_id uuid not null,
  restaurant_id uuid not null,
  branch_id uuid not null,
  decision_id uuid not null,
  reason text not null check (reason=btrim(reason,U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF') and length(reason) between 1 and 240
    and reason !~ '[[:cntrl:]]'),
  created_at timestamptz not null default clock_timestamp(),
  foreign key(organization_id,restaurant_id,branch_id,request_id)
    references public.web_order_requests(organization_id,restaurant_id,branch_id,id) on delete restrict,
  foreign key(organization_id,restaurant_id,branch_id,decision_id)
    references public.web_order_decisions(organization_id,restaurant_id,branch_id,decision_id) on delete restrict
);
alter table app.web_order_customer_rejection_reasons enable row level security;
alter table app.web_order_customer_rejection_reasons force row level security;
revoke all on app.web_order_customer_rejection_reasons from public,anon,authenticated,service_role;
create trigger web_order_customer_rejection_reasons_append_only
  before update or delete on app.web_order_customer_rejection_reasons
  for each row execute function app.enforce_audit_append_only();
create trigger web_order_customer_rejection_reasons_no_truncate
  before truncate on app.web_order_customer_rejection_reasons
  for each statement execute function app.enforce_audit_append_only();
comment on table app.web_order_customer_rejection_reasons is
  'Issue356: explicit future customer-public rejection text. Private forced-RLS append-only ledger, never a backfill or promotion of legacy staff-private reasons. Capability status is the only customer projection.';

create function app.pos_reject_web_order_customer(
  p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,
  p_request_id uuid,p_decision_id uuid,p_reason text
) returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_result jsonb; v_inserted integer;
begin
  -- Public text is already canonical at confirmation. Reject noncanonical
  -- outer Unicode whitespace rather than committing text the UI cannot decode.
  if p_reason is null or p_reason<>btrim(p_reason,U&'\0009\000A\000B\000C\000D\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF') then
    return jsonb_build_object('ok',false,'error','invalid_request','entity','web_order_request');
  end if;
  -- The existing writer proves caller, employee/PIN/device/tenant authority,
  -- locks the request and owns validation, expiry, conflicts and idempotency.
  v_result:=app.pos_reject_web_order(p_pin_session_id,p_device_id,p_device_session_token,
    p_request_id,p_decision_id,p_reason);
  if v_result->>'ok'='true' and v_result->>'status'='rejected'
     and v_result->>'replayed'='false' then
    insert into app.web_order_customer_rejection_reasons(
      request_id,organization_id,restaurant_id,branch_id,decision_id,reason)
    select w.id,w.organization_id,w.restaurant_id,w.branch_id,d.decision_id,btrim(p_reason)
      from public.web_order_requests w join public.web_order_decisions d on d.request_id=w.id
      where w.id=p_request_id and w.status='rejected' and d.decision='rejected'
        and d.decision_id=p_decision_id and w.rejection_reason=btrim(p_reason);
    get diagnostics v_inserted=row_count;
    if v_inserted<>1 then raise exception 'customer rejection mapping unavailable' using errcode='23514'; end if;
  end if;
  -- A replay (especially a historical staff-private rejection) never inserts.
  -- Any insert failure aborts this statement including the original decision.
  return v_result;
end; $$;
create function public.pos_reject_web_order_customer(
  p_pin_session_id uuid,p_device_id uuid,p_device_session_token text,
  p_request_id uuid,p_decision_id uuid,p_reason text
) returns jsonb language sql volatile security invoker set search_path='' as $$
  select app.pos_reject_web_order_customer(p_pin_session_id,p_device_id,p_device_session_token,
    p_request_id,p_decision_id,p_reason);
$$;
revoke all on function app.pos_reject_web_order_customer(uuid,uuid,text,uuid,uuid,text),
  public.pos_reject_web_order_customer(uuid,uuid,text,uuid,uuid,text) from public,anon,authenticated,service_role;
grant execute on function app.pos_reject_web_order_customer(uuid,uuid,text,uuid,uuid,text),
  public.pos_reject_web_order_customer(uuid,uuid,text,uuid,uuid,text) to authenticated;
alter function app.pos_reject_web_order_customer(uuid,uuid,text,uuid,uuid,text) owner to postgres;

create or replace function app.web_order_public_result(
  p_request public.web_order_requests,p_replayed boolean
) returns jsonb language sql volatile set search_path='' as $$
  select jsonb_build_object(
    'ok',true,'request_id',p_request.client_request_id,
    'status',case when p_request.status='pending' and p_request.expires_at<=clock_timestamp()
                  then 'expired' else p_request.status end,
    'expires_at',p_request.expires_at,
    'totals',jsonb_build_object('currency_code',p_request.currency_code,
      'subtotal_minor',p_request.subtotal_minor,'tax_total_minor',p_request.tax_total_minor,
      'grand_total_minor',p_request.grand_total_minor),'replayed',p_replayed)
    || coalesce((select jsonb_build_object('customer_rejection_reason',r.reason)
      from app.web_order_customer_rejection_reasons r join public.web_order_decisions d
        on d.request_id=r.request_id and d.decision_id=r.decision_id and d.decision='rejected'
      where p_request.status='rejected' and r.request_id=p_request.id
        and r.organization_id=p_request.organization_id and r.restaurant_id=p_request.restaurant_id
        and r.branch_id=p_request.branch_id),'{}'::jsonb);
$$;
revoke all on function app.web_order_public_result(public.web_order_requests,boolean)
  from public,anon,authenticated,service_role;

commit;
