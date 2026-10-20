-- Synthetic disposable database only; this file is never a production migration.
begin;
do $$ begin
  if current_database() !~ '^platform353_e2e_[0-9a-f]{12}$'
    or exists(select 1 from public.organizations where slug in ('platform353-local-a','platform353-local-b'))
    or exists(select 1 from public.web_order_requests)
    or exists(select 1 from app.pos_order_alert_registrations)
    or exists(select 1 from app.pos_order_alert_deliveries) then
    raise exception 'empty_synthetic_fixture_database_required';
  end if;
end; $$;
create schema platform353_acceptance;
revoke all on schema platform353_acceptance from public,anon,authenticated,service_role;
create function platform353_acceptance.id(label text) returns uuid language sql immutable as $$
  select md5('platform353-local-acceptance-'||label)::uuid; $$;
create temp table _e2e_tenants as select label,
  platform353_acceptance.id('org-'||label) org,
  platform353_acceptance.id('restaurant-'||label) restaurant,
  platform353_acceptance.id('branch-'||label) branch,
  platform353_acceptance.id('category-'||label) category,
  platform353_acceptance.id('item-'||label) item
  from unnest(array['a','b']) label;
insert into organizations(id,name,slug,default_currency,status)
  select org,'Synthetic '||label,'platform353-local-'||label,'ILS','active' from _e2e_tenants;
insert into restaurants(id,organization_id,name,timezone)
  select restaurant,org,'Synthetic restaurant '||label,'UTC' from _e2e_tenants;
insert into branches(id,organization_id,restaurant_id,name,timezone,kitchen_workflow_mode)
  select branch,org,restaurant,'Synthetic branch '||label,'UTC','printer_only' from _e2e_tenants;
insert into menu_categories(id,organization_id,restaurant_id,name)
  select category,org,restaurant,'Synthetic Food' from _e2e_tenants;
insert into menu_items(id,organization_id,restaurant_id,menu_category_id,name,base_price_minor,currency_code)
  select item,org,restaurant,category,'Stored item '||label,1000,'ILS' from _e2e_tenants;
insert into restaurant_storefront_profiles(restaurant_id,organization_id,storefront_branch_id,slug,display_name,
  pickup_enabled,opening_hours,is_published)
  select restaurant,org,branch,'platform353-local-'||label,'Synthetic restaurant '||label,true,
    jsonb_build_object('weekly',(select jsonb_agg(jsonb_build_object('dow',d,'open',o,'close',c))
      from generate_series(0,6) d cross join(values('00:00','12:00'),('11:00','00:00')) w(o,c)),
      'exceptions','[]'::jsonb),true from _e2e_tenants;
create temp table _e2e_staff as
  select n,t.*,platform353_acceptance.id('device-'||n) device,
    platform353_acceptance.id('pairing-'||n) pairing,platform353_acceptance.id('session-'||n) session,
    platform353_acceptance.id('staff-'||n) staff,platform353_acceptance.id('membership-'||n) membership,
    platform353_acceptance.id('employee-'||n) employee,platform353_acceptance.id('pin-'||n) pin,
    platform353_acceptance.id('shift-'||n) shift
  from generate_series(1,4) n join _e2e_tenants t on t.label=case when n=3 then 'b' else 'a' end;
insert into devices(id,organization_id,restaurant_id,branch_id,device_type)
  select device,org,restaurant,branch,'pos' from _e2e_staff where n<4;
insert into device_pairings(id,organization_id,restaurant_id,branch_id,device_id,status)
  select pairing,org,restaurant,branch,device,'active' from _e2e_staff where n<4;
insert into device_sessions(id,organization_id,restaurant_id,branch_id,device_id,device_pairing_id,session_token_ref,expires_at)
  select session,org,restaurant,branch,device,pairing,app.hash_provisioning_secret('synthetic-platform353-local-token-'||n),
    now()+interval '30 days' from _e2e_staff where n<4;
insert into app_users(id,email) select staff,'platform353-local-'||n||'@example.test' from _e2e_staff;
insert into memberships(id,app_user_id,organization_id,restaurant_id,branch_id,role)
  select membership,staff,org,restaurant,branch,'cashier' from _e2e_staff;
insert into employee_profiles(id,organization_id,restaurant_id,branch_id,app_user_id,membership_id,display_name)
  select employee,org,restaurant,branch,staff,membership,'Synthetic cashier '||n from _e2e_staff;
insert into pin_sessions(id,organization_id,restaurant_id,branch_id,device_session_id,employee_profile_id,resolved_membership_id,expires_at)
  select pin,org,restaurant,branch,session,employee,membership,now()+interval '6 hours' from _e2e_staff where n<4;
insert into shifts(id,organization_id,restaurant_id,branch_id,device_id,opened_by_employee_profile_id,resolved_membership_id,local_operation_id,status)
  select shift,org,restaurant,branch,device,employee,membership,'platform353-local-open-'||n,'open' from _e2e_staff where n<4;
insert into printer_devices(id,organization_id,restaurant_id,branch_id,display_name,connection_type,role,paper_width,is_enabled)
  select platform353_acceptance.id('printer-'||label),org,restaurant,branch,'Synthetic kitchen','network','kitchen','80mm',true from _e2e_tenants;
insert into kitchen_printer_readiness_reports(organization_id,restaurant_id,branch_id,device_id,capability,app_build,
  printer_purpose,transport_kind,paper_width,printer_fingerprint,secure_spool_available,unresolved_local_jobs,
  mode_revision,printer_assignment_id,expires_at)
  select org,restaurant,branch,device,'kitchen_printer_only_v1','synthetic-platform353-local','kitchen_ticket','network',
    '80mm',repeat('a',64),true,0,1,platform353_acceptance.id('printer-'||label),clock_timestamp()+interval '20 minutes'
  from _e2e_staff where n<4;
select app.set_pos_order_alerts(true,'Synthetic local integration only','platform353-local-acceptance');
-- Local fixture administration: fixed actions only, never arbitrary SQL. This
-- function is not part of the application or any production migration.
create function public.platform353_acceptance_fixture(p_action text,p_request uuid default null) returns jsonb
language plpgsql security definer set search_path='' as $$
declare v_id uuid; v_org uuid:=platform353_acceptance.id('org-a');
  v_rest uuid:=platform353_acceptance.id('restaurant-a'); v_branch uuid:=platform353_acceptance.id('branch-a');
begin
  if current_database() !~ '^platform353_e2e_[0-9a-f]{12}$' then raise exception 'local_fixture_database_required'; end if;
  if p_action='identity' then
    return jsonb_build_object('database',current_database(),'synthetic_only',true);
  elsif p_action='lookup' then
    select id into v_id from public.web_order_requests where client_request_id=p_request;
    return to_jsonb(v_id);
  elsif p_action='cardinality' then
    return jsonb_build_object('decisions',(select count(*) from public.web_order_decisions where request_id=p_request),
      'orders',(select count(distinct canonical_order_id) from public.web_order_decisions where request_id=p_request),
      'dispatches',(select count(*) from public.kitchen_print_dispatches where order_id=(select canonical_order_id from public.web_order_requests where id=p_request)),
      'attempts',(select count(*) from public.web_order_print_attempts where request_id=p_request and attempt_id is not null));
  elsif p_action='onboard_and_revoke' then
    insert into public.devices(id,organization_id,restaurant_id,branch_id,device_type)
      values(platform353_acceptance.id('device-4'),v_org,v_rest,v_branch,'pos');
    insert into public.device_pairings(id,organization_id,restaurant_id,branch_id,device_id,status)
      values(platform353_acceptance.id('pairing-4'),v_org,v_rest,v_branch,platform353_acceptance.id('device-4'),'active');
    insert into public.device_sessions(id,organization_id,restaurant_id,branch_id,device_id,device_pairing_id,session_token_ref,expires_at)
      values(platform353_acceptance.id('session-4'),v_org,v_rest,v_branch,platform353_acceptance.id('device-4'),platform353_acceptance.id('pairing-4'),
        app.hash_provisioning_secret('synthetic-platform353-local-token-4'),now()+interval '30 days');
    insert into public.pin_sessions(id,organization_id,restaurant_id,branch_id,device_session_id,employee_profile_id,resolved_membership_id,expires_at)
      values(platform353_acceptance.id('pin-4'),v_org,v_rest,v_branch,platform353_acceptance.id('session-4'),platform353_acceptance.id('employee-4'),
        platform353_acceptance.id('membership-4'),now()+interval '6 hours');
    insert into public.shifts(id,organization_id,restaurant_id,branch_id,device_id,opened_by_employee_profile_id,resolved_membership_id,local_operation_id,status)
      values(platform353_acceptance.id('shift-4'),v_org,v_rest,v_branch,platform353_acceptance.id('device-4'),platform353_acceptance.id('employee-4'),
        platform353_acceptance.id('membership-4'),'platform353-local-open-4','open');
    update public.device_pairings set status='revoked',revoked_at=clock_timestamp() where id=platform353_acceptance.id('pairing-2');
  elsif p_action='retry_due' then
    update app.pos_order_alert_deliveries set next_attempt_at=clock_timestamp()-interval '1 second' where request_id=p_request and state='queued';
  elsif p_action='offline' then
    update public.kitchen_printer_readiness_reports set expires_at=clock_timestamp()-interval '1 second' where device_id=platform353_acceptance.id('device-1');
  elsif p_action='attempt_count' then
    return to_jsonb((select count(*) from public.web_order_print_attempts where request_id=p_request and attempt_id is not null));
  elsif p_action='queue_snapshot' then
    return jsonb_build_object('rows',(select count(*) from app.pos_order_alert_deliveries),
      'attempts',(select coalesce(sum(attempt_count),0) from app.pos_order_alert_deliveries),
      'leased',(select count(*) from app.pos_order_alert_deliveries where state='leased'));
  elsif p_action='expire' then
    -- Advance the synthetic fixture's clock facts without waiting 15 minutes.
    -- Immutable production receipt guards deliberately reject this mutation;
    -- bypass USER triggers only inside this local-fixture-only transaction.
    -- The real expiry/status/terminal-delivery functions remain unchanged.
    perform set_config('session_replication_role','replica',true);
    update public.web_order_requests set created_at=clock_timestamp()-interval '20 minutes',
      expires_at=clock_timestamp()-interval '6 minutes',status_until=clock_timestamp()+interval '23 hours' where id=p_request;
    perform set_config('session_replication_role','origin',true);
  else raise exception 'unknown_local_fixture_action'; end if;
  return jsonb_build_object('ok',true);
end; $$;
revoke all on function public.platform353_acceptance_fixture(text,uuid) from public,anon,authenticated;
grant execute on function public.platform353_acceptance_fixture(text,uuid) to service_role;
commit;
