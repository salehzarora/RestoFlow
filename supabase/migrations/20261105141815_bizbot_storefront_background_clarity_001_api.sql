-- BIZBOT-STOREFRONT-BACKGROUND-CLARITY-001-API. Background-only companion.
-- Older media rows, slot writers, readers, recipes and Storage policies retain their definitions.
set local lock_timeout = '10s';
set local statement_timeout = '120s';

create function app.storefront_background_prefix_v1(p_restaurant uuid)
returns text language sql immutable strict set search_path = '' as $$
  select left(encode(sha256(convert_to('storefront-menu-background-v1:' || p_restaurant::text,'UTF8')),'hex'),32);
$$;

create table app.storefront_background_variants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  restaurant_id uuid not null,
  branch_id uuid not null,
  base_media_id uuid not null,
  base_hash text not null check (base_hash ~ '^[0-9a-f]{64}$'),
  source_snapshot jsonb not null check (jsonb_typeof(source_snapshot) = 'object'),
  content_hash text not null check (content_hash ~ '^[0-9a-f]{64}$' and content_hash <> base_hash),
  object_key text not null,
  width integer not null check (width between 1 and 2560),
  height integer not null check (height between 1 and 2560),
  bytes integer not null check (bytes between 1 and 524288),
  created_at timestamptz not null default now(),
  published_at timestamptz,
  foreign key (organization_id,restaurant_id,branch_id)
    references public.branches(organization_id,restaurant_id,id) on delete restrict,
  foreign key (organization_id,restaurant_id,base_media_id)
    references public.storefront_media(organization_id,restaurant_id,id) on delete restrict,
  unique (organization_id,restaurant_id,branch_id,base_media_id,source_snapshot),
  constraint storefront_background_key_v1 check (
    app.storefront_background_prefix_v1(restaurant_id) <> app.storefront_media_prefix(restaurant_id)
    and object_key = app.storefront_background_prefix_v1(restaurant_id) || '/' || content_hash || '.webp')
);
create index storefront_background_object_v1 on app.storefront_background_variants(object_key);
alter table app.storefront_background_variants enable row level security;
revoke all on app.storefront_background_variants from public,anon,authenticated,service_role;

-- Scope and generation are derived from the existing editorial base, never a caller path.
-- Parent eligibility includes the live w960 Storage object and the private source scope.
create function app.storefront_background_context_v1(p_o uuid,p_r uuid,p_b uuid,p_base uuid)
returns table(base_hash text,base_width integer,base_height integer,base_url text,
  source_bucket text,source_key text,source_snapshot jsonb)
language sql stable set search_path = '' as $$
  select m.content_hash,m.width,m.height,u.url,m.source_bucket,m.source_key,
         jsonb_build_object('storage_object_id',s.id,'storage_version',s.version,
            'storage_updated_at',to_char(s.updated_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
  from public.restaurant_storefront_profiles p
  join public.organizations o on o.id=p.organization_id and o.status='active' and o.deleted_at is null
  join public.restaurants r on r.organization_id=p.organization_id and r.id=p.restaurant_id and r.status='active' and r.deleted_at is null
  join public.branches b on b.organization_id=p.organization_id and b.restaurant_id=p.restaurant_id and b.id=p.storefront_branch_id and b.status='active' and b.deleted_at is null
  join public.storefront_media m on m.organization_id=p.organization_id and m.restaurant_id=p.restaurant_id and m.id=p_base
  join storage.objects s on s.bucket_id=m.source_bucket and s.name=m.source_key and s.id is not null and s.updated_at is not null
  cross join lateral (select app.storefront_content_media_url_v1(p_o,p_r,p_b,m.id) as url) u
  where p.organization_id=p_o and p.restaurant_id=p_r and p.storefront_branch_id=p_b and p.deleted_at is null
    and m.product_derivative_id is null and m.variant='w960' and u.url is not null;
$$;

create function app.storefront_background_authorize_v1(p_o uuid,p_r uuid)
returns void language plpgsql stable set search_path = '' as $$
begin
  if app.current_app_user_id() is null or p_o is null or p_r is null
     or not app.can_write_storefront_media(p_o,p_r) then
    raise exception 'background media permission denied' using errcode='42501';
  end if;
end; $$;

create function app.get_storefront_background_source_v1(p_organization_id uuid,p_restaurant_id uuid,p_branch_id uuid,p_base_media_id uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare c record;
begin
  perform app.storefront_background_authorize_v1(p_organization_id,p_restaurant_id);
  select * into c from app.storefront_background_context_v1(p_organization_id,p_restaurant_id,p_branch_id,p_base_media_id);
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
  return jsonb_build_object('ok',true,'base_media_id',p_base_media_id,'base_hash',c.base_hash,
    'base_width',c.base_width,'base_height',c.base_height,'source_bucket',c.source_bucket,
    'source_key',c.source_key,'source_snapshot',c.source_snapshot);
end; $$;

create function app.storefront_background_result_v1(v app.storefront_background_variants)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object('ok',true,'variant_id',v.id,'base_media_id',v.base_media_id,'object_key',v.object_key,
    'content_hash',v.content_hash,'width',v.width,'height',v.height,'bytes',v.bytes,
    'variant','bg2560','recipe','storefront-background-b1','state',case when v.published_at is null then 'staged' else 'published' end);
$$;

create function app.stage_storefront_background_variant_v1(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,
  p_branch_id uuid,p_base_media_id uuid,p_source_snapshot jsonb,p_expected_base_hash text,p_content_hash text,
  p_width integer,p_height integer,p_bytes integer)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c record; v app.storefront_background_variants%rowtype; actor uuid:=app.current_app_user_id();
  fp text; replay jsonb; result jsonb; ns text;
begin
  perform app.storefront_background_authorize_v1(p_organization_id,p_restaurant_id);
  if p_client_request_id is null then raise exception 'request id required' using errcode='42501'; end if;
  -- Match the existing publisher lock order. Different requests for the same parent serialize.
  perform 1 from public.restaurants where organization_id=p_organization_id and id=p_restaurant_id for update;
  select * into c from app.storefront_background_context_v1(p_organization_id,p_restaurant_id,p_branch_id,p_base_media_id);
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
  if c.source_snapshot is distinct from p_source_snapshot or c.base_hash is distinct from p_expected_base_hash then
    return jsonb_build_object('ok',false,'error','source_stale'); end if;
  ns:=app.storefront_background_prefix_v1(p_restaurant_id);
  if ns=app.storefront_media_prefix(p_restaurant_id) or p_content_hash is null or p_content_hash !~ '^[0-9a-f]{64}$'
    or p_content_hash=p_expected_base_hash or p_width is null or p_height is null or p_bytes is null
    or p_width not between 1 and 2560 or p_height not between 1 and 2560 or p_bytes not between 1 and 524288
    or p_width<=c.base_width or p_height<c.base_height or greatest(c.base_width,c.base_height)<>960
    or abs(p_width::bigint*c.base_height-p_height::bigint*c.base_width)>greatest(p_width,p_height) then
    return jsonb_build_object('ok',false,'error','invalid'); end if;
  fp:=md5(jsonb_build_array(p_organization_id,p_restaurant_id,p_branch_id,p_base_media_id,p_source_snapshot,
    p_expected_base_hash,p_content_hash,p_width,p_height,p_bytes)::text);
  replay:=app.management_idem_check(actor,p_client_request_id,'stage_storefront_background_variant_v1',fp);
  select * into v from app.storefront_background_variants where organization_id=p_organization_id and restaurant_id=p_restaurant_id
    and branch_id=p_branch_id and base_media_id=p_base_media_id and source_snapshot=p_source_snapshot for update;
  if found and (v.content_hash,v.width,v.height,v.bytes,v.base_hash) is distinct from
    (p_content_hash,p_width,p_height,p_bytes,p_expected_base_hash) then return jsonb_build_object('ok',false,'error','object_conflict'); end if;
  if replay is not null then
    if v.id is null or v.id::text is distinct from replay->>'variant_id' then return jsonb_build_object('ok',false,'error','stale_request'); end if;
    return app.storefront_background_result_v1(v);
  end if;
  if v.id is null then
    -- A hash may be shared by eligible rows, but declarations for its immutable bytes must agree.
    if exists(select 1 from app.storefront_background_variants a where a.object_key=ns||'/'||p_content_hash||'.webp'
      and (a.width,a.height,a.bytes) is distinct from (p_width,p_height,p_bytes)) then
      return jsonb_build_object('ok',false,'error','object_conflict'); end if;
    insert into app.storefront_background_variants(organization_id,restaurant_id,branch_id,base_media_id,base_hash,source_snapshot,
      content_hash,object_key,width,height,bytes) values(p_organization_id,p_restaurant_id,p_branch_id,p_base_media_id,p_expected_base_hash,
      p_source_snapshot,p_content_hash,ns||'/'||p_content_hash||'.webp',p_width,p_height,p_bytes) returning * into v;
    perform app.management_audit(p_organization_id,p_restaurant_id,p_branch_id,'settings.storefront.background.staged',null,
      jsonb_build_object('base_media_id',p_base_media_id,'variant_id',v.id));
  end if;
  result:=app.storefront_background_result_v1(v);
  replay:=app.management_claim_request(actor,p_client_request_id,'stage_storefront_background_variant_v1',fp,result);
  return coalesce(replay,result);
end; $$;

create function app.finalize_storefront_background_variant_v1(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_variant_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare c record; v app.storefront_background_variants%rowtype; actor uuid:=app.current_app_user_id();
  fp text; replay jsonb; result jsonb;
begin
  perform app.storefront_background_authorize_v1(p_organization_id,p_restaurant_id);
  if p_client_request_id is null then raise exception 'request id required' using errcode='42501'; end if;
  perform 1 from public.restaurants where organization_id=p_organization_id and id=p_restaurant_id for update;
  select * into v from app.storefront_background_variants where id=p_variant_id and organization_id=p_organization_id and restaurant_id=p_restaurant_id for update;
  if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
  select * into c from app.storefront_background_context_v1(p_organization_id,p_restaurant_id,v.branch_id,v.base_media_id);
  if not found or c.source_snapshot is distinct from v.source_snapshot or c.base_hash is distinct from v.base_hash then
    return jsonb_build_object('ok',false,'error','source_stale'); end if;
  if not exists(select 1 from storage.objects o where o.bucket_id='storefront-media' and o.name=v.object_key
    and o.metadata->>'mimetype'='image/webp' and o.metadata->>'size'=v.bytes::text) then
    return jsonb_build_object('ok',false,'error','object_mismatch'); end if;
  fp:=md5(jsonb_build_array(p_organization_id,p_restaurant_id,p_variant_id)::text);
  replay:=app.management_idem_check(actor,p_client_request_id,'finalize_storefront_background_variant_v1',fp);
  if replay is not null then
    if v.published_at is null then return jsonb_build_object('ok',false,'error','stale_request'); end if;
    return app.storefront_background_result_v1(v);
  end if;
  if v.published_at is null then
    update app.storefront_background_variants set published_at=now() where id=v.id returning * into v;
    perform app.management_audit(p_organization_id,p_restaurant_id,v.branch_id,'settings.storefront.background.published',null,
      jsonb_build_object('base_media_id',v.base_media_id,'variant_id',v.id));
  end if;
  result:=app.storefront_background_result_v1(v);
  replay:=app.management_claim_request(actor,p_client_request_id,'finalize_storefront_background_variant_v1',fp,result);
  return coalesce(replay,result);
end; $$;

create function public.get_storefront_background_source_v1(p_organization_id uuid,p_restaurant_id uuid,p_branch_id uuid,p_base_media_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
  select app.get_storefront_background_source_v1($1,$2,$3,$4); $$;
create function public.stage_storefront_background_variant_v1(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,
  p_branch_id uuid,p_base_media_id uuid,p_source_snapshot jsonb,p_expected_base_hash text,p_content_hash text,p_width integer,p_height integer,p_bytes integer)
returns jsonb language sql security invoker set search_path='' as $$
  select app.stage_storefront_background_variant_v1($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11); $$;
create function public.finalize_storefront_background_variant_v1(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_variant_id uuid)
returns jsonb language sql security invoker set search_path='' as $$
  select app.finalize_storefront_background_variant_v1($1,$2,$3,$4); $$;

-- Independent namespace and INSERT/SELECT policy. Never extend the legacy helper used by UPDATE/DELETE.
create function app.can_access_storefront_background_object_v1(p_name text,p_insert boolean)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from app.storefront_background_variants v
    cross join lateral app.storefront_background_context_v1(v.organization_id,v.restaurant_id,v.branch_id,v.base_media_id) c
    where v.object_key=p_name and app.can_write_storefront_media(v.organization_id,v.restaurant_id)
      and (not p_insert or v.published_at is null) and c.source_snapshot=v.source_snapshot and c.base_hash=v.base_hash);
$$;
create policy storefront_background_registered_select_v1 on storage.objects for select to authenticated
  using(bucket_id='storefront-media' and app.can_access_storefront_background_object_v1(name,false));
create policy storefront_background_registered_insert_v1 on storage.objects for insert to authenticated
  with check(bucket_id='storefront-media' and app.can_access_storefront_background_object_v1(name,true));

create function public.storefront_menu_v7(p_slug text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare m jsonb; expected_base_url text; manifest jsonb;
begin
  m:=public.storefront_menu_v6(p_slug);
  if m->>'ok' is distinct from 'true' or m#>>'{restaurant,slug}' is distinct from p_slug then return m; end if;
  expected_base_url:=m#>>'{content_v1,appearance,menu_background_url}';
  if expected_base_url is null then return m; end if;
  select jsonb_build_object('base_url',c.base_url,'variants',jsonb_build_array(
    jsonb_build_object('url',c.base_url,'width',c.base_width,'height',c.base_height),
    jsonb_build_object('url','/storage/v1/object/public/storefront-media/'||v.object_key,'width',v.width,'height',v.height))) into manifest
  from public.restaurant_storefront_profiles p
  join app.storefront_content_profiles content on content.organization_id=p.organization_id and content.restaurant_id=p.restaurant_id
    and content.storefront_branch_id=p.storefront_branch_id and content.deleted_at is null
  join app.storefront_background_variants v on v.organization_id=p.organization_id and v.restaurant_id=p.restaurant_id
    and v.branch_id=p.storefront_branch_id and v.base_media_id=(content.appearance->>'menu_background_media_id')::uuid and v.published_at is not null
  cross join lateral app.storefront_background_context_v1(v.organization_id,v.restaurant_id,v.branch_id,v.base_media_id) c
  join storage.objects high on high.bucket_id='storefront-media' and high.name=v.object_key and high.metadata->>'mimetype'='image/webp' and high.metadata->>'size'=v.bytes::text
  where p.slug=p_slug and p.is_published and p.deleted_at is null and c.base_url=expected_base_url and c.base_hash=v.base_hash and c.source_snapshot=v.source_snapshot;
  if manifest is null then return m; end if;
  return m||jsonb_build_object('menu_background_images_v1',manifest);
end; $$;

revoke all on function app.storefront_background_prefix_v1(uuid),app.storefront_background_context_v1(uuid,uuid,uuid,uuid),
  app.storefront_background_authorize_v1(uuid,uuid),app.storefront_background_result_v1(app.storefront_background_variants),
  app.get_storefront_background_source_v1(uuid,uuid,uuid,uuid),public.get_storefront_background_source_v1(uuid,uuid,uuid,uuid),
  app.stage_storefront_background_variant_v1(uuid,uuid,uuid,uuid,uuid,jsonb,text,text,integer,integer,integer),public.stage_storefront_background_variant_v1(uuid,uuid,uuid,uuid,uuid,jsonb,text,text,integer,integer,integer),
  app.finalize_storefront_background_variant_v1(uuid,uuid,uuid,uuid),public.finalize_storefront_background_variant_v1(uuid,uuid,uuid,uuid),
  app.can_access_storefront_background_object_v1(text,boolean),public.storefront_menu_v7(text) from public,anon,authenticated,service_role;
grant execute on function app.get_storefront_background_source_v1(uuid,uuid,uuid,uuid),public.get_storefront_background_source_v1(uuid,uuid,uuid,uuid),
  app.stage_storefront_background_variant_v1(uuid,uuid,uuid,uuid,uuid,jsonb,text,text,integer,integer,integer),public.stage_storefront_background_variant_v1(uuid,uuid,uuid,uuid,uuid,jsonb,text,text,integer,integer,integer),
  app.finalize_storefront_background_variant_v1(uuid,uuid,uuid,uuid),public.finalize_storefront_background_variant_v1(uuid,uuid,uuid,uuid),
  app.can_access_storefront_background_object_v1(text,boolean) to authenticated;
grant execute on function public.storefront_menu_v7(text) to anon,service_role;
alter function app.get_storefront_background_source_v1(uuid,uuid,uuid,uuid) owner to postgres;
alter function app.stage_storefront_background_variant_v1(uuid,uuid,uuid,uuid,uuid,jsonb,text,text,integer,integer,integer) owner to postgres;
alter function app.finalize_storefront_background_variant_v1(uuid,uuid,uuid,uuid) owner to postgres;
alter function app.can_access_storefront_background_object_v1(text,boolean) owner to postgres;
alter function public.storefront_menu_v7(text) owner to postgres;
