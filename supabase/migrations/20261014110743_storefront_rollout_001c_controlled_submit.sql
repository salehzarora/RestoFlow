-- STOREFRONT-ROLLOUT-001C-PREP: server-only, one-identity controlled intake.
-- Does not enable any channel, alter the public profile CHECK/reader, or replace
-- the existing submit/status/canonical functions. Private authentication and
-- exact normalized payload/capability binding remain the Edge permit's job.
begin;

create function app.submit_web_order_test_request(
  p_slug text,p_client_request_id uuid,p_status_token_hash text,p_order jsonb,
  p_test_organization_id uuid,p_test_restaurant_id uuid,p_test_branch_id uuid,
  p_test_request_id uuid,p_test_not_before timestamptz,p_test_expires_at timestamptz
) returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_result jsonb;
  v_now timestamptz;
begin
  -- This BEGIN/EXCEPTION block is a rollback boundary for the delegated submit
  -- too: a deadline crossed during any wait or successful write leaves no rows,
  -- received event or admission-counter mutation from this controlled call.
  if p_slug is distinct from 'mapsburger'
     or p_test_organization_id is null or p_test_restaurant_id is null
     or p_test_branch_id is null or p_client_request_id is null
     or p_test_request_id is null or p_client_request_id<>p_test_request_id
     or p_test_request_id::text !~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
     or p_test_not_before is null or p_test_expires_at is null then
    return jsonb_build_object('ok',false,'error','ordering_unavailable');
  end if;
  if not isfinite(p_test_not_before) or not isfinite(p_test_expires_at) then
    return jsonb_build_object('ok',false,'error','ordering_unavailable');
  end if;
  if p_test_expires_at<=p_test_not_before
     or p_test_expires_at-p_test_not_before>interval '15 minutes' then
    return jsonb_build_object('ok',false,'error','ordering_unavailable');
  end if;

  -- Preserve the ordinary submit's identity-before-channel lock order. The
  -- exact profile SHARE lock adds atomic expected-scope proof and prevents a
  -- profile writer moving this slug/branch while pricing/submission executes.
  perform pg_advisory_xact_lock(hashtextextended(
    p_test_restaurant_id::text||':'||p_client_request_id::text,0));
  perform 1 from public.restaurant_storefront_profiles p
    where p.slug=p_slug and p.organization_id=p_test_organization_id
      and p.restaurant_id=p_test_restaurant_id
      and p.storefront_branch_id=p_test_branch_id and p.deleted_at is null
    for share;
  if not found then
    return jsonb_build_object('ok',false,'error','ordering_unavailable');
  end if;
  perform 1 from public.web_order_channel_settings c
    where c.organization_id=p_test_organization_id
      and c.restaurant_id=p_test_restaurant_id and c.branch_id=p_test_branch_id
    for update;
  if not found then
    return jsonb_build_object('ok',false,'error','ordering_unavailable');
  end if;
  v_now:=clock_timestamp();
  if v_now<p_test_not_before or v_now>=p_test_expires_at then
    return jsonb_build_object('ok',false,'error','ordering_unavailable');
  end if;

  -- Delegate unchanged pricing, gates, abuse limits and idempotency. In
  -- particular, an exact replay may still resolve while channel intake is off.
  v_result:=app.submit_web_order_request(
    p_slug,p_client_request_id,p_status_token_hash,p_order);
  v_now:=clock_timestamp();
  if v_now<p_test_not_before or v_now>=p_test_expires_at then
    raise exception using errcode='RWC01',message='controlled submission window closed';
  end if;
  return v_result;
exception when sqlstate 'RWC01' then
  return jsonb_build_object('ok',false,'error','ordering_unavailable');
end;
$$;

create function public.submit_web_order_test_request(
  p_slug text,p_client_request_id uuid,p_status_token_hash text,p_order jsonb,
  p_test_organization_id uuid,p_test_restaurant_id uuid,p_test_branch_id uuid,
  p_test_request_id uuid,p_test_not_before timestamptz,p_test_expires_at timestamptz
) returns jsonb language sql volatile security invoker set search_path = '' as $$
  select app.submit_web_order_test_request(
    p_slug,p_client_request_id,p_status_token_hash,p_order,
    p_test_organization_id,p_test_restaurant_id,p_test_branch_id,
    p_test_request_id,p_test_not_before,p_test_expires_at);
$$;

revoke all on function
  app.submit_web_order_test_request(text,uuid,text,jsonb,uuid,uuid,uuid,uuid,timestamptz,timestamptz),
  public.submit_web_order_test_request(text,uuid,text,jsonb,uuid,uuid,uuid,uuid,timestamptz,timestamptz)
  from public,anon,authenticated,service_role;
grant execute on function
  app.submit_web_order_test_request(text,uuid,text,jsonb,uuid,uuid,uuid,uuid,timestamptz,timestamptz),
  public.submit_web_order_test_request(text,uuid,text,jsonb,uuid,uuid,uuid,uuid,timestamptz,timestamptz)
  to service_role;
alter function app.submit_web_order_test_request(
  text,uuid,text,jsonb,uuid,uuid,uuid,uuid,timestamptz,timestamptz) owner to postgres;

commit;
