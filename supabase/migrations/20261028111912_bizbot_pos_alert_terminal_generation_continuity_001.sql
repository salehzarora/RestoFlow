-- BIZBOT-POS-BACKGROUND-ALERTS-RELIABILITY-001 — terminal continuity.
-- Prerequisites: six unchanged, already-applied observation/ownership migrations
-- 20261026144133 through 20261027142721. Never rerun or rewrite those in production.
-- Function source is the retained post-reconciliation live baseline; change only
-- busy-branch terminal election and current-generation terminal synthesis.
-- No registration, token, consent, print, public RPC, ACL or RLS changes.
begin;

-- Refuse a concurrent/unknown function or privilege change. The atomic
-- application envelope separately verifies exact history/prerequisite versions.
do $baseline$
declare v_target oid:=pg_catalog.to_regprocedure('app.pos_claim_order_alert_deliveries(integer)');
begin
  if not exists(select 1 from pg_catalog.pg_proc p where p.oid=v_target
    and pg_catalog.pg_get_userbyid(p.proowner)='postgres'
    and pg_catalog.encode(pg_catalog.sha256(pg_catalog.convert_to(pg_catalog.pg_get_functiondef(p.oid),'UTF8')),'hex')
      ='05f03d466977ea01000b749d8508091726ddcde3bd2d42b8652e73c4378d8756'
    and (select array_agg(a::text order by a::text) from unnest(p.proacl) a)
      =array['postgres=X/postgres','service_role=X/postgres']::text[])
  then raise exception 'alert terminal baseline mismatch' using errcode='55000';end if;
end;
$baseline$;

CREATE OR REPLACE FUNCTION app.pos_claim_order_alert_deliveries(p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_now timestamptz:=clock_timestamp(); v_rows jsonb; v_branches uuid[];
begin
  if not app.lock_pos_order_alert_writes() then return jsonb_build_object('ok',false,'error','unavailable');end if;
  v_now:=clock_timestamp();
  if p_limit is null or p_limit not between 1 and 10 then return jsonb_build_object('ok',false,'error','invalid_request'); end if;
  if not coalesce((select enabled from app.pos_order_alert_settings order by revision desc limit 1),false) then
    return jsonb_build_object('ok',true,'server_time',v_now,'deliveries','[]'::jsonb); end if;
  -- Idle tenants are excluded from election. Least recently scanned *busy*
  -- branches rotate, and SKIP LOCKED prevents an overlapping worker from
  -- spending a second batch on the same branch during this transaction.
  select coalesce(array_agg(q.branch_id),'{}'::uuid[]) into v_branches from (
    select c.branch_id from app.pos_order_alert_branch_cursors c where exists(
      select 1 from app.pos_order_alert_registrations r where r.branch_id=c.branch_id
      and app.pos_order_alert_authority(r)>v_now and (
        exists(select 1 from public.web_order_requests w
          join app.online_order_notification_requests live on live.request_id=w.id
          join app.pos_order_alert_settings s on s.revision=r.setting_revision
          where w.organization_id=r.organization_id and w.restaurant_id=r.restaurant_id and w.branch_id=r.branch_id
            and w.status='pending' and w.expires_at>v_now and w.created_at>=r.registered_at and w.created_at>=s.created_at
            and not exists(select 1 from app.pos_order_alert_deliveries d where d.registration_id=r.id
              and d.generation=r.generation and d.request_id=w.id and d.kind='pending'))
        or exists(select 1 from app.pos_order_alert_deliveries d join public.web_order_requests w on w.id=d.request_id
          where d.registration_id=r.id and (
            (d.generation=r.generation and d.state in ('queued','leased') and d.next_attempt_at<=v_now and d.attempt_count<3
              and (d.lease_until is null or d.lease_until<=v_now))
            or (d.kind='pending'
              and w.organization_id=r.organization_id and w.restaurant_id=r.restaurant_id and w.branch_id=r.branch_id
              and w.expires_at>=v_now-interval '2 minutes' and w.expires_at<=v_now+interval '15 minutes'
              and (w.expires_at<=v_now or exists(select 1 from public.web_order_decisions dec where dec.request_id=w.id))
              and not exists(select 1 from app.pos_order_alert_deliveries term where term.registration_id=r.id
                and term.generation=r.generation and term.request_id=d.request_id and term.kind='terminal'))))))
      order by c.scanned_at,c.branch_id for update of c skip locked limit 10) q;
  update app.pos_order_alert_branch_cursors set scanned_at=v_now where branch_id=any(v_branches);

  -- At most 100 new pending rows (10 busy branches x 10) plus 100 terminal
  -- rows per call: 200 total independent of tenant count. Claims remain <=10.
  -- Existing uniqueness is the fanout backstop.
  insert into app.pos_order_alert_deliveries(registration_id,generation,request_id,kind)
  select q.registration_id,q.generation,q.request_id,'pending' from unnest(v_branches) b(branch_id)
  cross join lateral(select r.id registration_id,r.generation,w.id request_id
    from app.pos_order_alert_registrations r join public.web_order_requests w
      on w.organization_id=r.organization_id and w.restaurant_id=r.restaurant_id and w.branch_id=r.branch_id
    join public.web_order_request_events e on e.request_id=w.id and e.event_type='received'
    join app.online_order_notification_requests live on live.request_id=w.id
    join app.pos_order_alert_settings s on s.revision=r.setting_revision
    where r.branch_id=b.branch_id and app.pos_order_alert_authority(r)>v_now
      and w.created_at>=s.created_at and w.created_at>=r.registered_at and w.status='pending' and w.expires_at>v_now
      and not exists(select 1 from app.pos_order_alert_deliveries d where d.registration_id=r.id
        and d.generation=r.generation and d.request_id=w.id and d.kind='pending')
    order by w.created_at,w.id,r.id limit 10) q on conflict do nothing;
  -- A foreground renewal/token change fences old sends, not the obligation to
  -- refresh an already targeted request after resolution. Keep every historical
  -- row/generation unchanged and send only through this SAME current registration.
  -- A pending record is coverage evidence, not proof that FCM reached Android:
  -- queued/leased/abandoned rows also cover an uncertain old send/finish race.
  -- Fold historical generations BEFORE the global 100-row bound. The finite
  -- deadline horizon matches native cancel-hint acceptance and skips old backlog.
  insert into app.pos_order_alert_deliveries(registration_id,generation,request_id,kind)
  select q.registration_id,q.generation,q.request_id,'terminal' from (
    select distinct r.id registration_id,r.generation,w.id request_id,w.created_at
    from app.pos_order_alert_registrations r join public.web_order_requests w
      on w.organization_id=r.organization_id and w.restaurant_id=r.restaurant_id and w.branch_id=r.branch_id
    where r.branch_id=any(v_branches) and app.pos_order_alert_authority(r)>v_now
      and w.expires_at>=v_now-interval '2 minutes' and w.expires_at<=v_now+interval '15 minutes'
      and (w.expires_at<=v_now or exists(select 1 from public.web_order_decisions dec where dec.request_id=w.id))
      and exists(select 1 from app.pos_order_alert_deliveries d where d.registration_id=r.id
        and d.request_id=w.id and d.kind='pending')
      and not exists(select 1 from app.pos_order_alert_deliveries term where term.registration_id=r.id
        and term.generation=r.generation and term.request_id=w.id and term.kind='terminal')
  ) q order by q.created_at,q.request_id,q.registration_id limit 100 on conflict do nothing;
  with stale as(select d.id from app.pos_order_alert_deliveries d
    join app.pos_order_alert_registrations r on r.id=d.registration_id join public.web_order_requests w on w.id=d.request_id
    where d.state in ('queued','leased') and (r.generation<>d.generation or app.pos_order_alert_authority(r) is null
      or (d.attempt_count>=3 and (d.lease_until is null or d.lease_until<=v_now))
      or (d.kind='pending' and (w.status<>'pending' or w.expires_at<=v_now)))
    order by d.created_at,d.id for update of d skip locked limit 100)
  update app.pos_order_alert_deliveries d set state='abandoned',lease_id=null,lease_until=null from stale s where s.id=d.id;
  with branch_candidates as (
    select q.id,q.created_at,row_number() over(partition by b.branch_id order by q.created_at,q.id) tenant_position
    from unnest(v_branches) b(branch_id) cross join lateral(
      select d.id,d.created_at from app.pos_order_alert_deliveries d
      join app.pos_order_alert_registrations r on r.id=d.registration_id and r.generation=d.generation
      join public.web_order_requests w on w.id=d.request_id
      where r.branch_id=b.branch_id and d.state in ('queued','leased') and d.next_attempt_at<=v_now and d.attempt_count<3
        and (d.lease_until is null or d.lease_until<=v_now) and app.pos_order_alert_authority(r)>v_now
        and (d.kind='terminal' or (w.status='pending' and w.expires_at>v_now))
      order by d.created_at,d.id for update of d skip locked limit 10) q
  ), candidates as(select id from branch_candidates order by tenant_position,created_at,id limit p_limit), leased as (
    update app.pos_order_alert_deliveries d set state='leased',attempt_count=d.attempt_count+1,
      lease_id=gen_random_uuid(),lease_until=v_now+interval '2 minutes'
    from candidates c where d.id=c.id returning d.*
  ) select coalesce(jsonb_agg(jsonb_build_object('delivery_id',l.id,'lease_id',l.lease_id,'registration_id',r.id,
    'generation',l.generation,'fcm_token',r.fcm_token,'kind',l.kind,'request_id',l.request_id,
    'expires_at',w.expires_at,'authority_expires_at',app.pos_order_alert_authority(r))),'[]') into v_rows
    from leased l join app.pos_order_alert_registrations r on r.id=l.registration_id join public.web_order_requests w on w.id=l.request_id;
  return jsonb_build_object('ok',true,'server_time',v_now,'deliveries',v_rows);
end; $function$;

commit;
