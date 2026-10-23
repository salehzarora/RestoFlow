-- BIZBOT-STOREFRONT-FEATURED-ITEMS-001: bounded presentation selection only.
-- Existing public readers/writers, menu values and operational gates unchanged.
begin;

create function app.valid_storefront_featured_item_ids(p_ids uuid[])
returns boolean language sql immutable set search_path='' as $$
  select p_ids is not null and cardinality(p_ids) between 0 and 12
    and (cardinality(p_ids)=0 or (array_ndims(p_ids)=1 and array_lower(p_ids,1)=1))
    and not exists(select 1 from unnest(p_ids) x(id) where id is null)
    and (select count(*)=count(distinct id) from unnest(p_ids) x(id))
    and p_ids=coalesce((select array_agg(id order by id) from unnest(p_ids) x(id)),'{}'::uuid[]);
$$;
revoke all on function app.valid_storefront_featured_item_ids(uuid[]) from public,anon,authenticated,service_role;
-- Preserve the profile's existing service-role table access/constraints; this
-- input-only helper grants neither a table read nor a mutation capability.
grant execute on function app.valid_storefront_featured_item_ids(uuid[]) to service_role;

alter table public.restaurant_storefront_profiles
  add column featured_item_ids uuid[] not null default '{}'::uuid[],
  add constraint restaurant_storefront_profiles_featured_item_ids_valid
    check (app.valid_storefront_featured_item_ids(featured_item_ids));

create function app.set_restaurant_storefront_featured_items(
  p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,
  p_expected_version integer,p_patch jsonb)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare
  v_actor uuid:=app.current_app_user_id();
  v_rank integer;
  v_profile public.restaurant_storefront_profiles%rowtype;
  v_value jsonb;
  v_id uuid;
  v_ids uuid[]:='{}'::uuid[];
  v_fingerprint text;
  v_replay jsonb;
  v_result jsonb;
  v_old jsonb;
  v_new jsonb;
  c_entity constant text:='restaurant_storefront_profile';
  c_operation constant text:='set_restaurant_storefront_featured_items';
begin
  if v_actor is null then
    raise exception 'set_restaurant_storefront_featured_items: authentication required' using errcode='42501';
  end if;
  if p_client_request_id is null or p_organization_id is null or p_restaurant_id is null
    or p_expected_version is null or p_expected_version<0 then
    raise exception 'set_restaurant_storefront_featured_items: invalid required input' using errcode='42501';
  end if;
  v_rank:=app.actor_rank_in_scope(p_organization_id,p_restaurant_id,null);
  if v_rank=0 then
    raise exception 'set_restaurant_storefront_featured_items: no covering membership' using errcode='42501';
  end if;
  if v_rank<2 then
    perform app.management_audit(p_organization_id,p_restaurant_id,null,
      'settings.storefront.update_denied',null,
      jsonb_build_object('restaurant_id',p_restaurant_id,'setting','storefront_profile'));
    return jsonb_build_object('ok',false,'error','permission_denied','entity',c_entity);
  end if;
  if p_patch is null or jsonb_typeof(p_patch)<>'object' then
    return jsonb_build_object('ok',false,'error','invalid','reason','patch_not_object','entity',c_entity);
  end if;
  if not (p_patch ? 'featured_item_ids') or (select count(*) from jsonb_object_keys(p_patch))<>1 then
    return jsonb_build_object('ok',false,'error','invalid','reason','featured_item_ids_invalid','field','featured_item_ids','entity',c_entity);
  end if;
  -- Same hierarchy/profile lock order as existing generic/Home/media writers.
  perform 1 from public.restaurants r where r.id=p_restaurant_id
    and r.organization_id=p_organization_id and r.deleted_at is null for update;
  if not found then return jsonb_build_object('ok',false,'error','not_found','entity',c_entity); end if;
  select * into v_profile from public.restaurant_storefront_profiles p
    where p.restaurant_id=p_restaurant_id and p.organization_id=p_organization_id
      and p.deleted_at is null for update;
  if not found then return jsonb_build_object('ok',false,'error','not_found','entity',c_entity); end if;
  if app.actor_rank_in_scope(p_organization_id,p_restaurant_id,null)<2 then
    raise exception 'set_restaurant_storefront_featured_items: authority changed' using errcode='42501';
  end if;
  -- Bind the complete RAW patch before UUID case/set normalization. A replay
  -- of a committed request survives later catalog changes but not revocation.
  v_fingerprint:=md5(jsonb_build_object('org',p_organization_id,'restaurant',p_restaurant_id,
    'expected_version',p_expected_version,'patch',p_patch)::text);
  v_replay:=app.management_idem_check(v_actor,p_client_request_id,c_operation,v_fingerprint);
  if v_replay is not null then return v_replay; end if;
  if v_profile.version<>p_expected_version then
    return jsonb_build_object('ok',false,'error','version_conflict','entity',c_entity,
      'restaurant_id',p_restaurant_id,'version',v_profile.version,
      'slug',v_profile.slug,'is_published',v_profile.is_published);
  end if;
  if jsonb_typeof(p_patch->'featured_item_ids') is distinct from 'array' then
    return jsonb_build_object('ok',false,'error','invalid','reason','featured_item_ids_invalid','field','featured_item_ids','entity',c_entity);
  end if;
  if jsonb_array_length(p_patch->'featured_item_ids')>12 then
    return jsonb_build_object('ok',false,'error','invalid','reason','featured_item_ids_invalid','field','featured_item_ids','entity',c_entity);
  end if;
  for v_value in select value from jsonb_array_elements(p_patch->'featured_item_ids') loop
    if jsonb_typeof(v_value)<>'string' or char_length(v_value#>>'{}')<>36
      or (v_value#>>'{}') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      return jsonb_build_object('ok',false,'error','invalid','reason','featured_item_ids_invalid','field','featured_item_ids','entity',c_entity);
    end if;
    v_id:=(v_value#>>'{}')::uuid;
    if v_id=any(v_ids) then
      return jsonb_build_object('ok',false,'error','invalid','reason','featured_item_ids_invalid','field','featured_item_ids','entity',c_entity);
    end if;
    v_ids:=array_append(v_ids,v_id);
  end loop;
  if not exists(select 1 from public.branches b where b.id=v_profile.storefront_branch_id
    and b.organization_id=p_organization_id and b.restaurant_id=p_restaurant_id
    and b.status='active' and b.deleted_at is null) then
    return jsonb_build_object('ok',false,'error','invalid','reason','branch_invalid','entity',c_entity);
  end if;
  -- This private management eligibility check can configure an unpublished
  -- profile; it never publishes a product. The public DTO filters again using
  -- the actual v2 menu snapshot, not this broader saved selection.
  if exists(select 1 from unnest(v_ids) selected(id) where not exists(
    select 1 from public.menu_items i join public.menu_categories c
      on c.id=i.menu_category_id and c.organization_id=i.organization_id and c.restaurant_id=i.restaurant_id
    where i.id=selected.id and i.organization_id=p_organization_id and i.restaurant_id=p_restaurant_id
      and i.is_active and i.deleted_at is null and (i.branch_id is null or i.branch_id=v_profile.storefront_branch_id)
      and c.is_active and c.deleted_at is null and (c.branch_id is null or c.branch_id=v_profile.storefront_branch_id))) then
    return jsonb_build_object('ok',false,'error','invalid','reason','featured_item_ids_invalid','field','featured_item_ids','entity',c_entity);
  end if;
  select coalesce(array_agg(id order by id),'{}'::uuid[]) into v_ids from unnest(v_ids) selected(id);
  v_result:=jsonb_build_object('ok',true,'idempotent_replay',false,'entity',c_entity,
    'restaurant_id',p_restaurant_id,'version',v_profile.version+1,'slug',v_profile.slug,'is_published',v_profile.is_published);
  v_replay:=app.management_claim_request(v_actor,p_client_request_id,c_operation,v_fingerprint,v_result);
  if v_replay is not null then return v_replay; end if;
  v_old:=to_jsonb(v_profile);
  update public.restaurant_storefront_profiles set featured_item_ids=v_ids,version=v_profile.version+1
    where organization_id=p_organization_id and restaurant_id=p_restaurant_id;
  select to_jsonb(p) into v_new from public.restaurant_storefront_profiles p where p.restaurant_id=p_restaurant_id;
  perform app.management_audit(p_organization_id,p_restaurant_id,null,'settings.storefront.updated',v_old,v_new);
  return v_result;
end; $$;

create function public.set_restaurant_storefront_featured_items(
  p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,
  p_expected_version integer,p_patch jsonb)
returns jsonb language sql volatile security invoker set search_path='' as $$
  select app.set_restaurant_storefront_featured_items(p_client_request_id,p_organization_id,
    p_restaurant_id,p_expected_version,p_patch);
$$;
revoke all on function app.set_restaurant_storefront_featured_items(uuid,uuid,uuid,integer,jsonb),
  public.set_restaurant_storefront_featured_items(uuid,uuid,uuid,integer,jsonb) from public,anon,authenticated,service_role;
grant execute on function app.set_restaurant_storefront_featured_items(uuid,uuid,uuid,integer,jsonb),
  public.set_restaurant_storefront_featured_items(uuid,uuid,uuid,integer,jsonb) to authenticated;

create function public.storefront_menu_v3(p_slug text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_menu jsonb; v_saved uuid[]; v_public jsonb;
begin
  v_menu:=public.storefront_menu_v2(p_slug);
  if v_menu->>'ok' is distinct from 'true' then return v_menu; end if;
  if v_menu#>>'{restaurant,slug}' is distinct from p_slug then
    return jsonb_build_object('ok',false,'error','not_found','entity','storefront_menu');
  end if;
  select p.featured_item_ids into v_saved from public.restaurant_storefront_profiles p
    join public.organizations o on o.id=p.organization_id
    join public.restaurants r on r.organization_id=p.organization_id and r.id=p.restaurant_id
    join public.branches b on b.organization_id=p.organization_id and b.restaurant_id=p.restaurant_id and b.id=p.storefront_branch_id
  where p.slug=p_slug and p.deleted_at is null and p.is_published
    and o.status='active' and o.deleted_at is null and r.status='active' and r.deleted_at is null
    and b.status='active' and b.deleted_at is null and coalesce(b.timezone,r.timezone) is not null
    and coalesce(r.currency_override,o.default_currency)='ILS' and (not b.tax_enabled or b.tax_mode='exclusive');
  if not found then return jsonb_build_object('ok',false,'error','not_found','entity','storefront_menu'); end if;
  -- The PUBLIC serialized array contains no raw private/stale selection IDs.
  -- Only IDs already emitted by this exact menu snapshot may leave the server.
  select coalesce(jsonb_agg(item->'id' order by ordinal),'[]'::jsonb) into v_public
    from jsonb_array_elements(v_menu->'items') with ordinality x(item,ordinal)
    where (item->>'id')::uuid=any(v_saved);
  return v_menu||jsonb_build_object('featured_item_ids',v_public);
end; $$;
revoke all on function public.storefront_menu_v3(text) from public,anon,authenticated,service_role;
grant execute on function public.storefront_menu_v3(text) to anon,service_role;
comment on function public.storefront_menu_v3(text) is
  'BIZBOT-STOREFRONT-FEATURED-ITEMS-001: same-snapshot v2 once plus server-intersected public featured IDs. No raw saved-ID disclosure, ranking or menu/ordering authority.';
comment on function app.set_restaurant_storefront_featured_items(uuid,uuid,uuid,integer,jsonb) is
  'BIZBOT-STOREFRONT-FEATURED-ITEMS-001: existing-profile manager CAS, full raw single-key identity, fresh authorization before replay and after lock wait; presentation selection only.';
commit;
