-- BIZBOT-STOREFRONT-VISUAL-PARITY-001-MEDIA. Local candidate only.
-- Product presentation is separate from menu_items.image_path and every
-- editorial/receipt pointer. c4, its two variants and all byte caps are unchanged.
set local lock_timeout='10s';
set local statement_timeout='120s';

create table app.storefront_product_derivatives (
 id uuid primary key default gen_random_uuid(),
 organization_id uuid not null, restaurant_id uuid not null, item_id uuid not null,
 original_key text not null, original_snapshot jsonb not null,
 candidate_key text not null, candidate_snapshot jsonb not null,
 treatment text not null check(treatment in ('original','cutout')),
 expected_selection_version bigint not null check(expected_selection_version>=0),
 created_at timestamptz not null default now(),
 unique(organization_id,restaurant_id,id),
 foreign key(organization_id,restaurant_id,item_id) references public.menu_items(organization_id,restaurant_id,id) on delete restrict,
 check(jsonb_typeof(original_snapshot)='object' and jsonb_typeof(candidate_snapshot)='object'),
 check(length(original_key) between 1 and 512 and length(candidate_key) between 1 and 512),
 check((treatment='original' and candidate_key=original_key) or (treatment='cutout' and candidate_key<>original_key))
);
create table app.storefront_product_selections (
 organization_id uuid not null, restaurant_id uuid not null, item_id uuid not null,
 derivative_id uuid not null, version bigint not null check(version>0),
 primary key(organization_id,restaurant_id,item_id),
 foreign key(organization_id,restaurant_id,item_id) references public.menu_items(organization_id,restaurant_id,id) on delete restrict,
 foreign key(organization_id,restaurant_id,derivative_id) references app.storefront_product_derivatives(organization_id,restaurant_id,id) on delete restrict
);
alter table app.storefront_product_derivatives enable row level security;
alter table app.storefront_product_selections enable row level security;
revoke all on app.storefront_product_derivatives,app.storefront_product_selections from public,anon,authenticated,service_role;

alter table public.storefront_media add column product_derivative_id uuid;
alter table public.storefront_media add constraint storefront_media_product_scope
 foreign key(organization_id,restaurant_id,product_derivative_id)
 references app.storefront_product_derivatives(organization_id,restaurant_id,id) on delete restrict;
alter table public.storefront_media add constraint storefront_media_product_shape check(
 product_derivative_id is null or (source_bucket='menu-images' and item_source_snapshot is null));
-- Content-addressed bytes can be shared, publication associations cannot.
drop index public.storefront_media_legacy_object_key_idx;
create unique index storefront_media_legacy_object_key_idx on public.storefront_media(object_key)
 where product_derivative_id is null and not(source_bucket='menu-images' and variant='w480');
drop index public.storefront_media_live_source_idx;
create unique index storefront_media_live_source_idx on public.storefront_media(organization_id,restaurant_id,source_bucket,source_key,variant)
 where product_derivative_id is null and published_at is not null and unpublished_at is null;
create unique index storefront_media_product_content_idx on public.storefront_media(product_derivative_id,variant,content_hash)
 where product_derivative_id is not null;
create unique index storefront_media_product_live_idx on public.storefront_media(product_derivative_id,variant)
 where product_derivative_id is not null and published_at is not null and unpublished_at is null;

create function app.storefront_product_authorize_v1(p_org uuid,p_restaurant uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
 if app.current_app_user_id() is null or p_org is null or p_restaurant is null
 or app.actor_rank_in_scope(p_org,p_restaurant,null)<2
 or not exists(select 1 from public.restaurants where id=p_restaurant and organization_id=p_org and deleted_at is null) then
  raise exception 'storefront product: manager authority required' using errcode='42501';
 end if;
end; $$;

create function app.storefront_product_candidate_snapshot_v1(p_org uuid,p_restaurant uuid,p_item uuid,p_original text,p_candidate text)
returns jsonb language sql stable set search_path='' as $$
 select jsonb_build_object('storage_object_id',o.id,'storage_version',o.version,
 'storage_updated_at',to_char(o.updated_at at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
 from storage.objects o cross join lateral app.menu_image_scope(o.name) s
 join public.menu_items i on i.organization_id=s.organization_id and i.restaurant_id=s.restaurant_id
 and i.id=s.menu_item_id and i.branch_id is not distinct from s.branch_id
 where o.bucket_id='menu-images' and o.name=p_candidate and o.id is not null and o.updated_at is not null
 and i.organization_id=p_org and i.restaurant_id=p_restaurant and i.id=p_item
 and i.image_path=p_original and i.deleted_at is null and i.is_active;
$$;
create function app.storefront_product_current_v1(p_id uuid,p_org uuid,p_restaurant uuid)
returns boolean language sql stable set search_path='' as $$
 select exists(select 1 from app.storefront_product_derivatives d
 where d.id=p_id and d.organization_id=p_org and d.restaurant_id=p_restaurant
 and d.original_snapshot=app.storefront_item_source_snapshot(p_org,p_restaurant,d.original_key)
 and d.candidate_snapshot=app.storefront_product_candidate_snapshot_v1(p_org,p_restaurant,d.item_id,d.original_key,d.candidate_key));
$$;

create function app.get_storefront_product_original_v1(p_organization_id uuid,p_restaurant_id uuid,p_item_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare k text; s jsonb; v bigint; chosen uuid;
begin
 perform app.storefront_product_authorize_v1(p_organization_id,p_restaurant_id);
 select image_path into k from public.menu_items where organization_id=p_organization_id and restaurant_id=p_restaurant_id
 and id=p_item_id and deleted_at is null and is_active;
 s:=app.storefront_item_source_snapshot(p_organization_id,p_restaurant_id,k);
 if s is null then return jsonb_build_object('ok',false,'error','source_not_found'); end if;
 select version,derivative_id into v,chosen from app.storefront_product_selections where organization_id=p_organization_id and restaurant_id=p_restaurant_id and item_id=p_item_id;
 return jsonb_build_object('ok',true,'source_key',k,'source_snapshot',s,'selection_version',coalesce(v,0),'selected_derivative_id',chosen);
end; $$;

create function app.register_storefront_product_derivative_v1(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_item_id uuid,
 p_original_key text,p_original_snapshot jsonb,p_candidate_key text,p_treatment text,p_expected_selection_version bigint)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=app.current_app_user_id(); fp text; replay jsonb; result jsonb; candidate jsonb; v bigint; ident uuid:=gen_random_uuid();
begin
 perform app.storefront_product_authorize_v1(p_organization_id,p_restaurant_id);
 if p_client_request_id is null then raise exception 'request id required' using errcode='42501'; end if;
 if p_treatment is null or p_treatment not in ('original','cutout') or p_original_key is null or p_candidate_key is null
 or length(p_original_key)>512 or length(p_candidate_key)>512 or p_original_snapshot is null or jsonb_typeof(p_original_snapshot)<>'object'
 or p_expected_selection_version is null or p_expected_selection_version<0
 or (p_treatment='original')<>(p_original_key=p_candidate_key) then return jsonb_build_object('ok',false,'error','invalid'); end if;
 perform 1 from public.restaurants where id=p_restaurant_id and organization_id=p_organization_id for update;
 fp:=md5(jsonb_build_array(p_organization_id,p_restaurant_id,p_item_id,p_original_key,p_original_snapshot,p_candidate_key,p_treatment,p_expected_selection_version)::text);
 replay:=app.management_idem_check(actor,p_client_request_id,'register_storefront_product_derivative_v1',fp);
 if p_original_snapshot is distinct from app.storefront_item_source_snapshot(p_organization_id,p_restaurant_id,p_original_key)
 or not exists(select 1 from public.menu_items where id=p_item_id and organization_id=p_organization_id and restaurant_id=p_restaurant_id and image_path=p_original_key and deleted_at is null and is_active)
 then return jsonb_build_object('ok',false,'error','source_stale'); end if;
 candidate:=app.storefront_product_candidate_snapshot_v1(p_organization_id,p_restaurant_id,p_item_id,p_original_key,p_candidate_key);
 if candidate is null then return jsonb_build_object('ok',false,'error','source_not_found'); end if;
 if p_treatment='cutout' and not exists(select 1 from storage.objects where bucket_id='menu-images' and name=p_candidate_key and metadata->>'mimetype'='image/png')
 then return jsonb_build_object('ok',false,'error','invalid'); end if;
 if replay is not null then
  if not app.storefront_product_current_v1((replay->>'derivative_id')::uuid,p_organization_id,p_restaurant_id) then return jsonb_build_object('ok',false,'error','source_stale'); end if;
  return replay;
 end if;
 select version into v from app.storefront_product_selections where organization_id=p_organization_id and restaurant_id=p_restaurant_id and item_id=p_item_id;
 if coalesce(v,0)<>p_expected_selection_version then return jsonb_build_object('ok',false,'error','selection_stale'); end if;
 result:=jsonb_build_object('ok',true,'derivative_id',ident,'candidate_key',p_candidate_key);
 perform app.management_claim_request(actor,p_client_request_id,'register_storefront_product_derivative_v1',fp,result);
 insert into app.storefront_product_derivatives(id,organization_id,restaurant_id,item_id,original_key,original_snapshot,candidate_key,candidate_snapshot,treatment,expected_selection_version)
 values(ident,p_organization_id,p_restaurant_id,p_item_id,p_original_key,p_original_snapshot,p_candidate_key,candidate,p_treatment,p_expected_selection_version);
 perform app.management_audit(p_organization_id,p_restaurant_id,null,'settings.storefront.product.registered',null,jsonb_build_object('derivative_id',ident,'item_id',p_item_id,'treatment',p_treatment));
 return result;
end; $$;

create function app.get_storefront_product_source_v1(p_organization_id uuid,p_restaurant_id uuid,p_derivative_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d app.storefront_product_derivatives%rowtype;
begin
 perform app.storefront_product_authorize_v1(p_organization_id,p_restaurant_id);
 if not app.storefront_product_current_v1(p_derivative_id,p_organization_id,p_restaurant_id) then return jsonb_build_object('ok',false,'error','source_stale'); end if;
 select * into d from app.storefront_product_derivatives where id=p_derivative_id and organization_id=p_organization_id and restaurant_id=p_restaurant_id;
 return jsonb_build_object('ok',true,'source_key',d.candidate_key,'source_snapshot',d.candidate_snapshot);
end; $$;

create function app.stage_storefront_product_media_v1(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_derivative_id uuid,
 p_source_key text,p_source_snapshot jsonb,p_variant text,p_content_hash text,p_width integer,p_height integer,p_bytes integer)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=app.current_app_user_id(); d app.storefront_product_derivatives%rowtype; m public.storefront_media%rowtype;
 fp text; replay jsonb; result jsonb; k text; ident uuid;
begin
 perform app.storefront_product_authorize_v1(p_organization_id,p_restaurant_id);
 if p_client_request_id is null then raise exception 'request id required' using errcode='42501'; end if;
 if p_variant is null or p_variant not in ('w480','w960') or p_content_hash is null or p_content_hash !~ '^[0-9a-f]{64}$'
 or p_width is null or p_height is null or least(p_width,p_height)<1 or greatest(p_width,p_height)>(case p_variant when 'w480' then 480 else 960 end)
 or p_bytes is null or p_bytes not between 1 and 524288 then return jsonb_build_object('ok',false,'error','invalid','reason','dimensions_invalid'); end if;
 perform 1 from public.restaurants where id=p_restaurant_id and organization_id=p_organization_id for update;
 if not app.storefront_product_current_v1(p_derivative_id,p_organization_id,p_restaurant_id) then return jsonb_build_object('ok',false,'error','source_stale'); end if;
 select * into d from app.storefront_product_derivatives where id=p_derivative_id;
 if p_source_key is distinct from d.candidate_key or p_source_snapshot is distinct from d.candidate_snapshot then return jsonb_build_object('ok',false,'error','source_stale'); end if;
 fp:=md5(jsonb_build_array(p_organization_id,p_restaurant_id,p_derivative_id,p_source_key,p_source_snapshot,p_variant,p_content_hash,p_width,p_height,p_bytes)::text);
 replay:=app.management_idem_check(actor,p_client_request_id,'stage_storefront_product_media_v1',fp);
 if replay is not null then
  select * into m from public.storefront_media where id=(replay->>'media_id')::uuid and product_derivative_id=p_derivative_id;
  if not found then return jsonb_build_object('ok',false,'error','stale_request'); end if;
  return jsonb_set(replay,'{state}',to_jsonb(case when m.published_at is null then 'staged' when m.unpublished_at is null then 'published' else 'retracted' end));
 end if;
 k:=app.storefront_media_prefix(p_restaurant_id)||'/'||p_content_hash||'.webp';
 if exists(select 1 from public.storefront_media where object_key=k and (organization_id<>p_organization_id or restaurant_id<>p_restaurant_id)) then raise exception 'foreign content address' using errcode='42501'; end if;
 if exists(select 1 from public.storefront_media where object_key=k and (width<>p_width or height<>p_height or bytes<>p_bytes)) then return jsonb_build_object('ok',false,'error','content_mismatch'); end if;
 select * into m from public.storefront_media where product_derivative_id=p_derivative_id and variant=p_variant and content_hash=p_content_hash;
 ident:=coalesce(m.id,gen_random_uuid());
 result:=jsonb_build_object('ok',true,'media_id',ident,'object_key',k,'source_bucket','menu-images','source_key',d.candidate_key,'variant',p_variant,'source_mismatch',false,
 'state',case when m.published_at is null then 'staged' when m.unpublished_at is null then 'published' else 'retracted' end);
 perform app.management_claim_request(actor,p_client_request_id,'stage_storefront_product_media_v1',fp,result);
 if m.id is null then
  insert into public.storefront_media(id,organization_id,restaurant_id,source_bucket,source_key,variant,object_key,content_hash,width,height,bytes,product_derivative_id)
  values(ident,p_organization_id,p_restaurant_id,'menu-images',d.candidate_key,p_variant,k,p_content_hash,p_width,p_height,p_bytes,p_derivative_id);
  perform app.management_audit(p_organization_id,p_restaurant_id,null,'settings.storefront.product.staged',null,jsonb_build_object('media_id',ident,'derivative_id',p_derivative_id));
 end if;
 return result;
end; $$;

create function app.finalize_storefront_product_media_v1(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_media_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=app.current_app_user_id(); m public.storefront_media%rowtype; fp text; replay jsonb; result jsonb;
begin
 perform app.storefront_product_authorize_v1(p_organization_id,p_restaurant_id);
 if p_client_request_id is null then raise exception 'request id required' using errcode='42501'; end if;
 perform 1 from public.restaurants where id=p_restaurant_id and organization_id=p_organization_id for update;
 select * into m from public.storefront_media where id=p_media_id and organization_id=p_organization_id and restaurant_id=p_restaurant_id and product_derivative_id is not null for update;
 if not found then return jsonb_build_object('ok',false,'error','not_found'); end if;
 if not app.storefront_product_current_v1(m.product_derivative_id,p_organization_id,p_restaurant_id) then return jsonb_build_object('ok',false,'error','source_stale'); end if;
 if not exists(select 1 from storage.objects where bucket_id='storefront-media' and name=m.object_key and metadata->>'mimetype'='image/webp' and metadata->>'size'=m.bytes::text)
 then return jsonb_build_object('ok',false,'error','object_mismatch'); end if;
 fp:=md5(jsonb_build_array(p_organization_id,p_restaurant_id,p_media_id)::text);
 replay:=app.management_idem_check(actor,p_client_request_id,'finalize_storefront_product_media_v1',fp);
 if replay is not null then
  if m.published_at is null or m.unpublished_at is not null then return jsonb_build_object('ok',false,'error','stale_request'); end if;
  return replay;
 end if;
 -- Never replace a selected pair under its readers: a fresh logical choice
 -- gets its own registration; a failed/replayed rung leaves the old selection.
 if exists(select 1 from app.storefront_product_selections where derivative_id=m.product_derivative_id)
 and (m.published_at is null or m.unpublished_at is not null) then return jsonb_build_object('ok',false,'error','stale_request'); end if;
 result:=jsonb_build_object('ok',true,'media_id',m.id,'object_key',m.object_key,'state','published','already_published',m.published_at is not null and m.unpublished_at is null,
 'republished',m.unpublished_at is not null,'replaced_media_id',null,'profile_version',null);
 perform app.management_claim_request(actor,p_client_request_id,'finalize_storefront_product_media_v1',fp,result);
 update public.storefront_media set unpublished_at=greatest(now(),published_at)
 where product_derivative_id=m.product_derivative_id and variant=m.variant and id<>m.id and published_at is not null and unpublished_at is null;
 update public.storefront_media set published_at=coalesce(published_at,now()),unpublished_at=null where id=m.id;
 perform app.management_audit(p_organization_id,p_restaurant_id,null,'settings.storefront.product.published',null,jsonb_build_object('media_id',m.id,'derivative_id',m.product_derivative_id));
 return result;
end; $$;

create function app.select_storefront_product_derivative_v1(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_derivative_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid:=app.current_app_user_id(); d app.storefront_product_derivatives%rowtype; s app.storefront_product_selections%rowtype;
 fp text; replay jsonb; result jsonb;
begin
 perform app.storefront_product_authorize_v1(p_organization_id,p_restaurant_id);
 if p_client_request_id is null then raise exception 'request id required' using errcode='42501'; end if;
 perform 1 from public.restaurants where id=p_restaurant_id and organization_id=p_organization_id for update;
 if not app.storefront_product_current_v1(p_derivative_id,p_organization_id,p_restaurant_id) then return jsonb_build_object('ok',false,'error','source_stale'); end if;
 select * into d from app.storefront_product_derivatives where id=p_derivative_id;
 select * into s from app.storefront_product_selections where organization_id=p_organization_id and restaurant_id=p_restaurant_id and item_id=d.item_id;
 fp:=md5(jsonb_build_array(p_organization_id,p_restaurant_id,p_derivative_id)::text);
 replay:=app.management_idem_check(actor,p_client_request_id,'select_storefront_product_derivative_v1',fp);
 if replay is not null then
  if s.derivative_id is distinct from d.id then return jsonb_build_object('ok',false,'error','stale_request'); end if;
  return replay;
 end if;
 if coalesce(s.version,0)<>d.expected_selection_version then return jsonb_build_object('ok',false,'error','selection_stale'); end if;
 if (select count(distinct m.variant) from public.storefront_media m where m.product_derivative_id=d.id and m.published_at is not null and m.unpublished_at is null
 and exists(select 1 from storage.objects o where o.bucket_id='storefront-media' and o.name=m.object_key and o.metadata->>'mimetype'='image/webp' and o.metadata->>'size'=m.bytes::text))<>2
 then return jsonb_build_object('ok',false,'error','media_unavailable'); end if;
 result:=jsonb_build_object('ok',true,'derivative_id',d.id,'selection_version',coalesce(s.version,0)+1);
 perform app.management_claim_request(actor,p_client_request_id,'select_storefront_product_derivative_v1',fp,result);
 insert into app.storefront_product_selections(organization_id,restaurant_id,item_id,derivative_id,version)
 values(p_organization_id,p_restaurant_id,d.item_id,d.id,coalesce(s.version,0)+1)
 on conflict(organization_id,restaurant_id,item_id) do update set derivative_id=excluded.derivative_id,version=excluded.version;
 perform app.management_audit(p_organization_id,p_restaurant_id,null,'settings.storefront.product.selected',to_jsonb(s),result);
 return result;
end; $$;

create function app.storefront_product_images_v1(p_org uuid,p_restaurant uuid,p_branch uuid)
returns jsonb language sql stable set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('item_id',i.id,
 'w480_url','/storage/v1/object/public/storefront-media/'||lo.object_key,'w960_url','/storage/v1/object/public/storefront-media/'||hi.object_key,
 'width480',lo.width,'height480',lo.height,'width960',hi.width,'height960',hi.height) order by i.id),'[]'::jsonb)
 from app.storefront_product_selections s join public.menu_items i on i.organization_id=s.organization_id and i.restaurant_id=s.restaurant_id and i.id=s.item_id
 join public.menu_categories c on c.organization_id=i.organization_id and c.restaurant_id=i.restaurant_id and c.id=i.menu_category_id
 join public.storefront_media lo on lo.product_derivative_id=s.derivative_id and lo.variant='w480' and lo.published_at is not null and lo.unpublished_at is null
 join public.storefront_media hi on hi.product_derivative_id=s.derivative_id and hi.variant='w960' and hi.published_at is not null and hi.unpublished_at is null
 where s.organization_id=p_org and s.restaurant_id=p_restaurant and i.is_active and i.deleted_at is null and (i.branch_id is null or i.branch_id=p_branch)
 and c.is_active and c.deleted_at is null and (c.branch_id is null or c.branch_id=p_branch)
 and app.storefront_product_current_v1(s.derivative_id,p_org,p_restaurant)
 and exists(select 1 from storage.objects o where o.bucket_id='storefront-media' and o.name=lo.object_key and o.metadata->>'mimetype'='image/webp' and o.metadata->>'size'=lo.bytes::text)
 and exists(select 1 from storage.objects o where o.bucket_id='storefront-media' and o.name=hi.object_key and o.metadata->>'mimetype'='image/webp' and o.metadata->>'size'=hi.bytes::text);
$$;


-- Existing semantics preserved; product associations excluded/protected.
create or replace function app.stage_storefront_media(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_source_bucket     text,
  p_source_key        text,
  p_variant           text,
  p_content_hash      text,
  p_width             integer,
  p_height            integer,
  p_bytes             integer,
  p_source_snapshot   jsonb default null
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor     uuid := app.current_app_user_id();
  v_rank      integer;
  v_fp        text;
  v_replay    jsonb;
  v_result    jsonb;
  v_box       integer;
  v_key       text;
  v_row       public.storefront_media%rowtype;
  v_id        uuid;
  v_source_ok boolean;
  v_is_item   boolean;
  v_snapshot  jsonb;
  c_entity constant text := 'storefront_media';
begin
  -- (a) authentication + required input
  if v_actor is null then
    raise exception 'stage_storefront_media: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null or p_organization_id is null or p_restaurant_id is null then
    raise exception 'stage_storefront_media: client_request_id, organization_id and restaurant_id are required' using errcode = '42501';
  end if;
  -- the restaurant must belong to the organization BEFORE any authority branch: a foreign or
  -- unknown restaurant raises like rank 0 (no typed answer, no audit row under a foreign id)
  if not exists (select 1 from public.restaurants r
                  where r.id = p_restaurant_id and r.organization_id = p_organization_id and r.deleted_at is null) then
    raise exception 'stage_storefront_media: restaurant not found in organization or soft-deleted' using errcode = '42501';
  end if;

  -- (b) authority: manager+ covering the restaurant; a denied caller learns nothing
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, null);
  if v_rank = 0 then
    raise exception 'stage_storefront_media: caller has no active membership covering the restaurant' using errcode = '42501';
  end if;
  if v_rank < 2 then
    perform app.management_audit(p_organization_id, p_restaurant_id, null,
      'settings.storefront.media.denied', null,
      jsonb_build_object('restaurant_id', p_restaurant_id, 'operation', 'stage'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', c_entity);
  end if;

  -- (c) input: exact enumerations (SQL IN on text: no prototype-style lookup exists here)
  if p_source_bucket is null or p_source_bucket not in ('menu-images', 'restaurant-logos') then
    return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'source_bucket_invalid', 'entity', c_entity);
  end if;
  if p_variant is null or p_variant not in ('w480', 'w960') then
    return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'variant_invalid', 'entity', c_entity);
  end if;
  v_is_item := p_source_bucket = 'menu-images' and p_variant = 'w480';
  if v_is_item and (p_source_snapshot is null or jsonb_typeof(p_source_snapshot) <> 'object') then
    return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'source_snapshot_required', 'entity', c_entity);
  end if;
  if p_source_key is null or length(p_source_key) not between 1 and 512 then
    return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'source_key_invalid', 'entity', c_entity);
  end if;
  if p_content_hash is null or p_content_hash !~ '^[0-9a-f]{64}$' then
    return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'content_hash_invalid', 'entity', c_entity);
  end if;
  v_box := case p_variant when 'w480' then 480 else 960 end;
  if p_width is null or p_height is null or p_width < 1 or p_height < 1 or greatest(p_width, p_height) > v_box then
    return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'dimensions_invalid', 'entity', c_entity);
  end if;
  if p_bytes is null or p_bytes < 1 or p_bytes > 524288 then
    return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'bytes_invalid', 'entity', c_entity);
  end if;

  -- (d) lock the restaurant row FIRST (serialises every media + profile write of it)
  perform 1 from public.restaurants r
   where r.id = p_restaurant_id and r.organization_id = p_organization_id and r.deleted_at is null
   for update;
  if not found then
    raise exception 'stage_storefront_media: restaurant not found in organization or soft-deleted' using errcode = '42501';
  end if;

  -- (e) idempotent replay (under the lock)
  v_fp := md5((jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id,
              'bucket', p_source_bucket, 'key', p_source_key, 'variant', p_variant,
              'hash', p_content_hash, 'width', p_width, 'height', p_height, 'bytes', p_bytes)
              || case when v_is_item then jsonb_build_object('source_snapshot', p_source_snapshot) else '{}'::jsonb end)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'stage_storefront_media', v_fp);
  -- The token was obtained BEFORE the Edge download; never bind old downloaded
  -- bytes to a replacement that arrived between download and stage. Replays
  -- re-read the current item/original too, before returning an upload target.
  if v_is_item then
    v_snapshot := app.storefront_item_source_snapshot(p_organization_id, p_restaurant_id, p_source_key);
    if v_snapshot is null then
      return jsonb_build_object('ok', false, 'error', 'source_not_found', 'entity', c_entity);
    end if;
    if v_snapshot is distinct from p_source_snapshot then
      return jsonb_build_object('ok', false, 'error', 'source_stale', 'entity', c_entity);
    end if;
  end if;
  if v_replay is not null then
    -- The replayed row may have been CANCELLED since (cancel deletes STAGED rows): a stale replay
    -- must not send the caller to upload under a key that is no longer registered. Otherwise the
    -- replay reports the row's CURRENT state (it may have been published or retracted since).
    select * into v_row from public.storefront_media sm
     where sm.id = (v_replay ->> 'media_id')::uuid
       and sm.organization_id = p_organization_id and sm.restaurant_id = p_restaurant_id;
    if not found then
      return jsonb_build_object('ok', false, 'error', 'stale_request', 'entity', c_entity);
    end if;
    if v_is_item and v_row.item_source_snapshot is distinct from v_snapshot then
      return jsonb_build_object('ok', false, 'error', 'source_stale', 'entity', c_entity);
    end if;
    return jsonb_set(v_replay, '{state}', to_jsonb(case when v_row.published_at is null then 'staged'
                                                       when v_row.unpublished_at is null then 'published'
                                                       else 'retracted' end));
  end if;

  -- (f) the PRIVATE original must exist now and belong to THIS organization + restaurant
  --     (path-derived scope, the same parsers the private buckets' policies use).
  if p_source_bucket = 'menu-images' then
    select exists (
      select 1 from storage.objects o
       cross join lateral app.menu_image_scope(o.name) s
       where o.bucket_id = 'menu-images' and o.name = p_source_key
         and s.organization_id = p_organization_id and s.restaurant_id = p_restaurant_id)
      into v_source_ok;
  else
    select exists (
      select 1 from storage.objects o
       cross join lateral app.restaurant_logo_scope(o.name) s
       where o.bucket_id = 'restaurant-logos' and o.name = p_source_key
         and s.organization_id = p_organization_id and s.restaurant_id = p_restaurant_id)
      into v_source_ok;
  end if;
  if not v_source_ok then
    return jsonb_build_object('ok', false, 'error', 'source_not_found', 'entity', c_entity);
  end if;

  -- (g) Public bytes may be shared; an item's publication association may not.
  -- Legacy logo/hero dedup remains one row per content address. Item rows use
  -- their own source + generation, so neither another item nor a profile slot
  -- can rebind an existing association. Restaurant locking serializes writers.
  v_key := app.storefront_media_prefix(p_restaurant_id) || '/' || p_content_hash || '.webp';
  if exists (select 1 from public.storefront_media sm where sm.object_key = v_key
             and (sm.organization_id <> p_organization_id or sm.restaurant_id <> p_restaurant_id)) then
    raise exception 'stage_storefront_media: content address owned by another scope' using errcode = '42501';
  end if;
  if exists (select 1 from public.storefront_media sm where sm.object_key = v_key
             and (sm.width <> p_width or sm.height <> p_height or sm.bytes <> p_bytes)) then
    return jsonb_build_object('ok', false, 'error', 'content_mismatch', 'entity', c_entity);
  end if;
  select * into v_row from public.storefront_media sm
   where sm.object_key = v_key and sm.product_derivative_id is null
     and case when v_is_item then
       sm.source_bucket = p_source_bucket and sm.source_key = p_source_key
       and sm.variant = p_variant and sm.item_source_snapshot = v_snapshot
     else not (sm.source_bucket = 'menu-images' and sm.variant = 'w480') end
   for update;
  if found then
    v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', c_entity,
      'media_id', v_row.id, 'object_key', v_row.object_key,
      'state', case when v_row.published_at is null then 'staged'
                    when v_row.unpublished_at is null then 'published' else 'retracted' end,
      'existing', true,
      -- the ROW's own identity (it may differ from the request: same bytes, other source)
      'source_bucket', v_row.source_bucket, 'source_key', v_row.source_key, 'variant', v_row.variant,
      'source_mismatch', (v_row.source_bucket, v_row.source_key, v_row.variant)
                           is distinct from (p_source_bucket, p_source_key, p_variant));
    v_replay := app.management_claim_request(v_actor, p_client_request_id, 'stage_storefront_media', v_fp, v_result);
    if v_replay is not null then
      return v_replay;
    end if;
    return v_result;
  end if;

  -- (h) new STAGED row: claim first (house form), then insert, then audit
  v_id := gen_random_uuid();
  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', c_entity,
    'media_id', v_id, 'object_key', v_key, 'state', 'staged', 'existing', false,
    'source_bucket', p_source_bucket, 'source_key', p_source_key, 'variant', p_variant, 'source_mismatch', false);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'stage_storefront_media', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;
  insert into public.storefront_media (id, organization_id, restaurant_id, source_bucket, source_key, variant,
                                       object_key, content_hash, width, height, bytes, published_at, unpublished_at, item_source_snapshot)
  values (v_id, p_organization_id, p_restaurant_id, p_source_bucket, p_source_key, p_variant,
          v_key, p_content_hash, p_width, p_height, p_bytes, null, null, v_snapshot)
  returning * into v_row;
  perform app.management_audit(p_organization_id, p_restaurant_id, null,
    'settings.storefront.media.staged', null, to_jsonb(v_row));
  return v_result;
end;
$$;

-- Existing semantics preserved; product associations excluded/protected.
create or replace function app.finalize_storefront_media(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_media_id          uuid
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor        uuid := app.current_app_user_id();
  v_rank         integer;
  v_fp           text;
  v_replay       jsonb;
  v_result       jsonb;
  v_snapshot jsonb;
  v_row          public.storefront_media%rowtype;
  v_old          public.storefront_media%rowtype;
  v_has_old      boolean;
  v_prof         public.restaurant_storefront_profiles%rowtype;
  v_has_prof     boolean;
  v_repoint      boolean := false;
  v_prof_version integer;
  v_meta         jsonb;
  v_size         text;
  v_republished  boolean;
  v_before       jsonb;
  v_after        jsonb;
  c_entity constant text := 'storefront_media';
begin
  if v_actor is null then
    raise exception 'finalize_storefront_media: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null or p_organization_id is null or p_restaurant_id is null or p_media_id is null then
    raise exception 'finalize_storefront_media: client_request_id, organization_id, restaurant_id and media_id are required' using errcode = '42501';
  end if;
  -- the restaurant must belong to the organization BEFORE any authority branch: a foreign or
  -- unknown restaurant raises like rank 0 (no typed answer, no audit row under a foreign id)
  if not exists (select 1 from public.restaurants r
                  where r.id = p_restaurant_id and r.organization_id = p_organization_id and r.deleted_at is null) then
    raise exception 'finalize_storefront_media: restaurant not found in organization or soft-deleted' using errcode = '42501';
  end if;
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, null);
  if v_rank = 0 then
    raise exception 'finalize_storefront_media: caller has no active membership covering the restaurant' using errcode = '42501';
  end if;
  if v_rank < 2 then
    perform app.management_audit(p_organization_id, p_restaurant_id, null,
      'settings.storefront.media.denied', null,
      jsonb_build_object('restaurant_id', p_restaurant_id, 'operation', 'finalize'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', c_entity);
  end if;

  -- lock order: restaurant -> profile -> media
  perform 1 from public.restaurants r
   where r.id = p_restaurant_id and r.organization_id = p_organization_id and r.deleted_at is null
   for update;
  if not found then
    raise exception 'finalize_storefront_media: restaurant not found in organization or soft-deleted' using errcode = '42501';
  end if;
  select * into v_prof from public.restaurant_storefront_profiles p
   where p.restaurant_id = p_restaurant_id and p.organization_id = p_organization_id and p.deleted_at is null
   for update;
  v_has_prof := found;
  perform app.storefront_content_lock_v1(p_organization_id,p_restaurant_id);

  v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id, 'media', p_media_id)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'finalize_storefront_media', v_fp);

  -- A REPLAY re-reads its row too (as the stage replay does): the stored answer is always a
  -- publication, so a row retracted since (or gone) makes that answer stale -- the caller must
  -- restart with a new request (which republishes RETRACTED -> LIVE), never be told "published".
  select * into v_row from public.storefront_media sm
   where sm.id = p_media_id and sm.organization_id = p_organization_id and sm.restaurant_id = p_restaurant_id
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', case when v_replay is null then 'not_found' else 'stale_request' end, 'entity', c_entity);
  end if;
  if v_replay is not null and (v_row.published_at is null or v_row.unpublished_at is not null) then
    return jsonb_build_object('ok', false, 'error', 'stale_request', 'entity', c_entity);
  end if;

  if v_row.product_derivative_id is not null then
    return jsonb_build_object('ok',false,'error','product_operation_required','entity',c_entity);
  end if;

  -- Freshness applies to initial publication, already-LIVE publication and
  -- idempotent replay. A cached success is never authority for a stale item.
  if v_row.source_bucket = 'menu-images' and v_row.variant = 'w480' then
    v_snapshot := app.storefront_item_source_snapshot(p_organization_id, p_restaurant_id, v_row.source_key);
    if v_snapshot is null then
      return jsonb_build_object('ok', false, 'error', 'source_not_found', 'entity', c_entity);
    end if;
    if v_row.item_source_snapshot is distinct from v_snapshot then
      return jsonb_build_object('ok', false, 'error', 'source_stale', 'entity', c_entity);
    end if;
  end if;

  -- The point-in-time object check: a storage.objects ROW exists under the registered content
  -- address and its DECLARED metadata says image/webp and exactly the staged size. It runs for
  -- EVERY outcome, a replay and an already-LIVE row included (the object could have been removed
  -- through the raw Storage API by a manager of the restaurant: the registration-keyed policies
  -- of READ-001 allow it). It is NOT a proof of the bytes: the metadata is what the storage API
  -- recorded for the upload, and the bytes are never read here, so neither their format nor
  -- their hash is verified (the canonical recipe is the Edge Function's; see the header).
  select o.metadata into v_meta from storage.objects o
   where o.bucket_id = 'storefront-media' and o.name = v_row.object_key;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'object_missing', 'entity', c_entity);
  end if;
  v_size := v_meta ->> 'size';
  if coalesce(v_meta ->> 'mimetype', '') <> 'image/webp'
     or v_size is null or v_size !~ '^[0-9]{1,9}$' or v_size::integer <> v_row.bytes then
    return jsonb_build_object('ok', false, 'error', 'object_mismatch', 'entity', c_entity);
  end if;
  if v_replay is not null then
    return v_replay;
  end if;

  if v_row.published_at is not null and v_row.unpublished_at is null then
    v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', c_entity,
      'media_id', v_row.id, 'object_key', v_row.object_key, 'state', 'published',
      'already_published', true, 'republished', false, 'replaced_media_id', null, 'profile_version', null);
    v_replay := app.management_claim_request(v_actor, p_client_request_id, 'finalize_storefront_media', v_fp, v_result);
    return coalesce(v_replay, v_result);
  end if;

  v_republished := v_row.unpublished_at is not null;

  -- same-source replacement: the LIVE row of the same (source, variant), if any
  select * into v_old from public.storefront_media sm
   where sm.organization_id = p_organization_id and sm.restaurant_id = p_restaurant_id
     and sm.product_derivative_id is null
     and sm.source_bucket = v_row.source_bucket and sm.source_key = v_row.source_key and sm.variant = v_row.variant
     and sm.id <> v_row.id and sm.published_at is not null and sm.unpublished_at is null
   for update;
  v_has_old := found;
  if v_has_old and v_has_prof and (v_prof.logo_media_id = v_old.id or v_prof.hero_media_id = v_old.id) then
    v_repoint := true;
  end if;
  if v_has_old and v_has_prof and app.storefront_content_media_in_use_v1(p_organization_id,p_restaurant_id,v_prof.storefront_branch_id,v_old.id) then
    v_repoint := true;
  end if;
  v_prof_version := case when v_repoint then v_prof.version + 1 else null end;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', c_entity,
    'media_id', v_row.id, 'object_key', v_row.object_key, 'state', 'published',
    'already_published', false, 'republished', v_republished,
    'replaced_media_id', case when v_has_old then v_old.id else null end,
    'profile_version', v_prof_version);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'finalize_storefront_media', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  if v_has_old then
    -- retract the old row FIRST (the LIVE-only unique index admits one LIVE row per source)
    v_before := to_jsonb(v_old);
    update public.storefront_media
       set unpublished_at = greatest(now(), published_at)
     where id = v_old.id
     returning * into v_old;
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, device_id,
                                     action, reason, old_values, new_values)
    values (p_organization_id, p_restaurant_id, null, v_actor, null,
            'settings.storefront.media.retracted', 'media_replaced', v_before, to_jsonb(v_old));
  end if;

  v_before := to_jsonb(v_row);
  update public.storefront_media
     set published_at = now(), unpublished_at = null
   where id = v_row.id
   returning * into v_row;
  perform app.management_audit(p_organization_id, p_restaurant_id, null,
    'settings.storefront.media.published', v_before, to_jsonb(v_row));

  if v_repoint then
    if app.storefront_content_media_in_use_v1(p_organization_id,p_restaurant_id,v_prof.storefront_branch_id,v_old.id) then
      perform app.storefront_content_repoint_media_v1(p_organization_id,p_restaurant_id,v_prof.storefront_branch_id,v_old.id,v_row.id);
    end if;
    -- move every profile pointer from the replaced row to this one, atomically (no blank slot)
    v_before := to_jsonb(v_prof);
    update public.restaurant_storefront_profiles p
       set logo_media_id = case when p.logo_media_id = v_old.id then v_row.id else p.logo_media_id end,
           hero_media_id = case when p.hero_media_id = v_old.id then v_row.id else p.hero_media_id end,
           version       = v_prof_version
     where p.restaurant_id = p_restaurant_id
     returning to_jsonb(p.*) into v_after;
    insert into public.audit_events (organization_id, restaurant_id, branch_id, actor_app_user_id, device_id,
                                     action, reason, old_values, new_values)
    values (p_organization_id, p_restaurant_id, null, v_actor, null,
            'settings.storefront.updated', 'media_replaced', v_before, v_after);
  end if;
  return v_result;
end;
$$;

-- Existing semantics preserved; product associations excluded/protected.
create or replace function app.list_storefront_media(p_organization_id uuid, p_restaurant_id uuid)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor  uuid := app.current_app_user_id();
  v_rank   integer;
  v_logo   uuid;
  v_hero   uuid;
  v_media  jsonb;
  c_entity constant text := 'storefront_media';
begin
  if v_actor is null then
    raise exception 'list_storefront_media: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', c_entity);
  end if;
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, null);
  if v_rank < 2 then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', c_entity);
  end if;
  if not exists (select 1 from public.restaurants r
                  where r.id = p_restaurant_id and r.organization_id = p_organization_id and r.deleted_at is null) then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', c_entity);
  end if;
  select p.logo_media_id, p.hero_media_id into v_logo, v_hero
    from public.restaurant_storefront_profiles p
   where p.restaurant_id = p_restaurant_id and p.organization_id = p_organization_id and p.deleted_at is null;
  select coalesce(jsonb_agg(x.j order by x.created_at desc, x.id), '[]'::jsonb) into v_media
    from (
      select sm.created_at, sm.id,
             jsonb_build_object(
               'id', sm.id, 'source_bucket', sm.source_bucket, 'source_key', sm.source_key, 'variant', sm.variant,
               'object_key', sm.object_key, 'content_hash', sm.content_hash,
               'width', sm.width, 'height', sm.height, 'bytes', sm.bytes,
               'state', case when sm.published_at is null then 'staged'
                             when sm.unpublished_at is null then 'published' else 'retracted' end,
               'published_at', sm.published_at, 'unpublished_at', sm.unpublished_at, 'created_at', sm.created_at,
               'in_use', to_jsonb(array_remove(array[
                          case when sm.id = v_logo then 'logo' end,
                          case when sm.id = v_hero then 'hero' end], null))) as j
        from public.storefront_media sm
       where sm.organization_id = p_organization_id and sm.restaurant_id = p_restaurant_id
         and sm.product_derivative_id is null
         and not (sm.source_bucket = 'menu-images' and sm.variant = 'w480')
       order by sm.created_at desc, sm.id
       limit 200
    ) x;
  return jsonb_build_object('ok', true, 'entity', c_entity, 'restaurant_id', p_restaurant_id,
    'media_prefix', app.storefront_media_prefix(p_restaurant_id), 'media', v_media);
end;
$$;

-- Existing semantics preserved; product associations excluded/protected.
create or replace function app.set_restaurant_storefront_profile(
  p_client_request_id uuid,
  p_organization_id   uuid,
  p_restaurant_id     uuid,
  p_expected_version  integer,
  p_patch             jsonb
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor        uuid := app.current_app_user_id();
  v_rank         integer;
  v_fp           text;
  v_replay       jsonb;
  v_result       jsonb;
  v_old          jsonb;
  v_new          jsonb;
  v_cur          public.restaurant_storefront_profiles%rowtype;
  v_exists       boolean;
  v_cur_version  integer;
  v_new_version  integer;
  v_key          text;
  v_val          jsonb;
  v_next         public.restaurant_storefront_profiles%rowtype;
  v_blockers     text[];
  v_media_id     uuid;
  v_restaurant_name text;
  c_allowed constant text[] := array[
    'slug', 'storefront_branch_id', 'display_name', 'tagline', 'public_city', 'public_address', 'public_phone',
    'primary_color', 'accent_color', 'visual_preset', 'locale_default', 'card_mode', 'motion',
    'pickup_enabled', 'paused_until', 'pause_reason', 'opening_hours', 'logo_media_id', 'hero_media_id', 'is_published'];
  c_entity constant text := 'restaurant_storefront_profile';
begin
  -- (a) authentication + required input
  if v_actor is null then
    raise exception 'set_restaurant_storefront_profile: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'set_restaurant_storefront_profile: client_request_id is required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null then
    raise exception 'set_restaurant_storefront_profile: organization_id and restaurant_id are required' using errcode = '42501';
  end if;
  if p_expected_version is null or p_expected_version < 0 then
    raise exception 'set_restaurant_storefront_profile: expected_version must be a non-negative integer' using errcode = '42501';
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'patch_not_object', 'entity', c_entity);
  end if;
  for v_key in select k from jsonb_object_keys(p_patch) k loop
    if not (v_key = any (c_allowed)) then
      return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'unknown_field', 'field', v_key, 'entity', c_entity);
    end if;
  end loop;

  -- (b) authority: named-role gate. A denied caller learns NOTHING about the
  --     profile (no leak); the denial is audited.
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, null);
  if v_rank = 0 then
    raise exception 'set_restaurant_storefront_profile: caller has no active membership covering the restaurant' using errcode = '42501';
  end if;
  if v_rank < 2 then
    perform app.management_audit(p_organization_id, p_restaurant_id, null,
      'settings.storefront.update_denied', null,
      jsonb_build_object('restaurant_id', p_restaurant_id, 'setting', 'storefront_profile'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', c_entity);
  end if;

  -- (c) lock the restaurant row FIRST (serialize writers; proves existence in-org)
  select r.name into v_restaurant_name
    from public.restaurants r
   where r.id = p_restaurant_id and r.organization_id = p_organization_id and r.deleted_at is null
   for update;
  if not found then
    raise exception 'set_restaurant_storefront_profile: restaurant not found in organization or soft-deleted' using errcode = '42501';
  end if;
  select * into v_cur
    from public.restaurant_storefront_profiles p
   where p.restaurant_id = p_restaurant_id and p.organization_id = p_organization_id and p.deleted_at is null
   for update;
  v_exists := found;
  v_cur_version := case when v_exists then v_cur.version else 0 end;
  v_old := case when v_exists then to_jsonb(v_cur) else null end;

  -- (d) idempotent replay (under the locks)
  v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id,
              'expected_version', p_expected_version, 'patch', p_patch)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'set_restaurant_storefront_profile', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  -- (e) compare-and-set: a stale write returns the CURRENT state, claims nothing
  if v_cur_version <> p_expected_version then
    return jsonb_build_object('ok', false, 'error', 'version_conflict', 'entity', c_entity,
      'restaurant_id', p_restaurant_id, 'version', v_cur_version,
      'slug', case when v_exists then v_cur.slug else null end,
      'is_published', case when v_exists then v_cur.is_published else false end);
  end if;

  -- (f) the next row = current (or defaults) overlaid with the patch, validated
  if v_exists then
    v_next := v_cur;
  else
    v_next.restaurant_id        := p_restaurant_id;
    v_next.organization_id      := p_organization_id;
    v_next.storefront_branch_id := null;
    v_next.slug                 := null;
    v_next.display_name         := left(btrim(v_restaurant_name), 60);
    v_next.primary_color        := '#13322a';
    v_next.accent_color         := '#e07b2c';
    v_next.visual_preset        := 'dark';
    v_next.locale_default       := 'ar';
    v_next.card_mode            := 'list';
    v_next.motion               := 'full';
    v_next.pickup_enabled       := true;
    v_next.delivery_enabled     := false;
    v_next.ordering_enabled     := false;
    v_next.opening_hours        := '{"weekly":[],"exceptions":[]}'::jsonb;
    v_next.is_published         := false;
  end if;

  for v_key, v_val in select k, p_patch -> k from jsonb_object_keys(p_patch) k loop
    case v_key
      when 'slug' then
        if jsonb_typeof(v_val) <> 'string' then return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'slug_invalid', 'entity', c_entity); end if;
        v_next.slug := v_val #>> '{}';
        if v_next.slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' or length(v_next.slug) not between 3 and 48
           or v_next.slug in ('api', 'order', 'admin', 'pos', 'kds', 'kiosk', 'app', 'ar', 'en', 'he', 'www', 's', 'r') then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'slug_invalid', 'entity', c_entity);
        end if;
        -- immutable in this slice (plan decision D4, OPEN QUESTION Q-029): a
        -- live row keeps the slug it was created with; no rename, no history
        if v_exists and v_cur.slug is not null and v_cur.slug <> v_next.slug then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'slug_immutable', 'entity', c_entity);
        end if;
        if exists (select 1 from public.restaurant_storefront_profiles q
                    where q.slug = v_next.slug and q.deleted_at is null and q.restaurant_id <> p_restaurant_id) then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'slug_taken', 'entity', c_entity);
        end if;
      when 'storefront_branch_id' then
        if jsonb_typeof(v_val) <> 'string' then return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'branch_invalid', 'entity', c_entity); end if;
        begin
          v_next.storefront_branch_id := (v_val #>> '{}')::uuid;
        exception when others then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'branch_invalid', 'entity', c_entity);
        end;
        if not exists (select 1 from public.branches b
                        where b.id = v_next.storefront_branch_id and b.organization_id = p_organization_id
                          and b.restaurant_id = p_restaurant_id and b.deleted_at is null) then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'branch_invalid', 'entity', c_entity);
        end if;
      when 'display_name' then
        if jsonb_typeof(v_val) <> 'string' or length(btrim(v_val #>> '{}')) not between 1 and 60 then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'display_name_invalid', 'entity', c_entity);
        end if;
        v_next.display_name := btrim(v_val #>> '{}');
      when 'tagline' then
        if jsonb_typeof(v_val) not in ('string', 'null') or length(coalesce(v_val #>> '{}', '')) > 90 then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'tagline_invalid', 'entity', c_entity);
        end if;
        v_next.tagline := nullif(btrim(coalesce(v_val #>> '{}', '')), '');
      when 'public_city' then
        if jsonb_typeof(v_val) not in ('string', 'null') or length(coalesce(v_val #>> '{}', '')) > 60 then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'public_city_invalid', 'entity', c_entity);
        end if;
        v_next.public_city := nullif(btrim(coalesce(v_val #>> '{}', '')), '');
      when 'public_address' then
        if jsonb_typeof(v_val) not in ('string', 'null') or length(coalesce(v_val #>> '{}', '')) > 80 then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'public_address_invalid', 'entity', c_entity);
        end if;
        v_next.public_address := nullif(btrim(coalesce(v_val #>> '{}', '')), '');
      when 'public_phone' then
        if jsonb_typeof(v_val) not in ('string', 'null') then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'public_phone_invalid', 'entity', c_entity);
        end if;
        v_next.public_phone := nullif(btrim(coalesce(v_val #>> '{}', '')), '');
        if v_next.public_phone is not null and v_next.public_phone !~ '^(\+[1-9][0-9]{6,14}|0[0-9]{1,2}[- ]?[0-9]{3}[- ]?[0-9]{4})$' then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'public_phone_invalid', 'entity', c_entity);
        end if;
      when 'primary_color' then
        if jsonb_typeof(v_val) <> 'string' or (v_val #>> '{}') !~ '^#[0-9A-Fa-f]{6}$' then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'primary_color_invalid', 'entity', c_entity);
        end if;
        v_next.primary_color := lower(v_val #>> '{}');
      when 'accent_color' then
        if jsonb_typeof(v_val) <> 'string' or (v_val #>> '{}') !~ '^#[0-9A-Fa-f]{6}$' then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'accent_color_invalid', 'entity', c_entity);
        end if;
        v_next.accent_color := lower(v_val #>> '{}');
      when 'visual_preset' then
        if jsonb_typeof(v_val) <> 'string' or (v_val #>> '{}') not in ('dark', 'light') then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'visual_preset_invalid', 'entity', c_entity);
        end if;
        v_next.visual_preset := v_val #>> '{}';
      when 'locale_default' then
        if jsonb_typeof(v_val) <> 'string' or (v_val #>> '{}') not in ('ar', 'he', 'en') then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'locale_default_invalid', 'entity', c_entity);
        end if;
        v_next.locale_default := v_val #>> '{}';
      when 'card_mode' then
        if jsonb_typeof(v_val) <> 'string' or (v_val #>> '{}') not in ('list', 'grid') then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'card_mode_invalid', 'entity', c_entity);
        end if;
        v_next.card_mode := v_val #>> '{}';
      when 'motion' then
        if jsonb_typeof(v_val) <> 'string' or (v_val #>> '{}') not in ('calm', 'full', 'lively') then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'motion_invalid', 'entity', c_entity);
        end if;
        v_next.motion := v_val #>> '{}';
      when 'pickup_enabled' then
        if jsonb_typeof(v_val) <> 'boolean' then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'pickup_enabled_invalid', 'entity', c_entity);
        end if;
        v_next.pickup_enabled := (v_val #>> '{}')::boolean;
      when 'paused_until' then
        if jsonb_typeof(v_val) not in ('string', 'null') then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'paused_until_invalid', 'entity', c_entity);
        end if;
        -- ONE canonical wire format (independent review, C3): an RFC 3339 /
        -- ISO 8601 instant with an EXPLICIT Z or offset, or null. Relative words
        -- ('tomorrow', 'now'), 'infinity' and offset-less strings - which Postgres
        -- would otherwise read in the caller's SESSION zone, i.e. UTC under
        -- PostgREST - are refused, so the pause instant is deterministic.
        if v_val #>> '{}' is not null
           and (v_val #>> '{}') !~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?(Z|[+-]\d{2}:\d{2})$' then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'paused_until_invalid', 'entity', c_entity);
        end if;
        begin
          v_next.paused_until := (v_val #>> '{}')::timestamptz;
        exception when others then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'paused_until_invalid', 'entity', c_entity);
        end;
      when 'pause_reason' then
        if jsonb_typeof(v_val) not in ('string', 'null') or length(coalesce(v_val #>> '{}', '')) > 120 then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'pause_reason_invalid', 'entity', c_entity);
        end if;
        v_next.pause_reason := nullif(btrim(coalesce(v_val #>> '{}', '')), '');
      when 'opening_hours' then
        if not app.storefront_opening_hours_is_valid(v_val) then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'opening_hours_invalid', 'entity', c_entity);
        end if;
        v_next.opening_hours := v_val;
      when 'logo_media_id', 'hero_media_id' then
        if jsonb_typeof(v_val) = 'null' then
          if v_key = 'logo_media_id' then v_next.logo_media_id := null; else v_next.hero_media_id := null; end if;
        else
          if jsonb_typeof(v_val) <> 'string' then
            return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', v_key || '_invalid', 'entity', c_entity);
          end if;
          v_media_id := null;
          begin
            select sm.id into v_media_id
              from public.storefront_media sm
             where sm.id = (v_val #>> '{}')::uuid
               and sm.organization_id = p_organization_id and sm.restaurant_id = p_restaurant_id
               and sm.product_derivative_id is null
               and not (sm.source_bucket = 'menu-images' and sm.variant = 'w480')
               and sm.published_at is not null and sm.unpublished_at is null;
          exception when others then
            return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', v_key || '_invalid', 'entity', c_entity);
          end;
          if v_media_id is null then
            return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', v_key || '_invalid', 'entity', c_entity);
          end if;
          if v_key = 'logo_media_id' then v_next.logo_media_id := v_media_id; else v_next.hero_media_id := v_media_id; end if;
        end if;
      when 'is_published' then
        if jsonb_typeof(v_val) <> 'boolean' then
          return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'is_published_invalid', 'entity', c_entity);
        end if;
        v_next.is_published := (v_val #>> '{}')::boolean;
      else
        return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'unknown_field', 'field', v_key, 'entity', c_entity);
    end case;
  end loop;

  if v_next.storefront_branch_id is null then
    return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'branch_missing', 'entity', c_entity);
  end if;
  if v_next.slug is null then
    return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'slug_missing', 'entity', c_entity);
  end if;

  -- (g) publishing preconditions (only when the row will be published)
  if v_next.is_published then
    v_blockers := app.storefront_publish_blockers(p_organization_id, p_restaurant_id,
                    v_next.storefront_branch_id, v_next.slug, v_next.opening_hours);
    if coalesce(array_length(v_blockers, 1), 0) > 0 then
      return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'publish_precondition',
        'detail', to_jsonb(v_blockers), 'entity', c_entity);
    end if;
  end if;

  -- (h) accepted: bump version exactly once, claim the ledger, mutate, audit.
  v_new_version := v_cur_version + 1;
  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', c_entity,
                'restaurant_id', p_restaurant_id, 'version', v_new_version,
                'slug', v_next.slug, 'is_published', v_next.is_published);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'set_restaurant_storefront_profile', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;

  if v_exists then
    update public.restaurant_storefront_profiles
       set storefront_branch_id = v_next.storefront_branch_id,
           slug            = v_next.slug,
           display_name    = v_next.display_name,
           tagline         = v_next.tagline,
           public_city     = v_next.public_city,
           public_address  = v_next.public_address,
           public_phone    = v_next.public_phone,
           primary_color   = v_next.primary_color,
           accent_color    = v_next.accent_color,
           visual_preset   = v_next.visual_preset,
           locale_default  = v_next.locale_default,
           card_mode       = v_next.card_mode,
           motion          = v_next.motion,
           pickup_enabled  = v_next.pickup_enabled,
           paused_until    = v_next.paused_until,
           pause_reason    = v_next.pause_reason,
           opening_hours   = v_next.opening_hours,
           logo_media_id   = v_next.logo_media_id,
           hero_media_id   = v_next.hero_media_id,
           is_published    = v_next.is_published,
           version         = v_new_version
     where restaurant_id = p_restaurant_id;
  else
    insert into public.restaurant_storefront_profiles (
      restaurant_id, organization_id, storefront_branch_id, slug, display_name, tagline, public_city, public_address,
      public_phone, primary_color, accent_color, visual_preset, locale_default, card_mode, motion, pickup_enabled,
      delivery_enabled, ordering_enabled, paused_until, pause_reason, opening_hours, logo_media_id, hero_media_id,
      is_published, version)
    values (
      p_restaurant_id, p_organization_id, v_next.storefront_branch_id, v_next.slug, v_next.display_name, v_next.tagline,
      v_next.public_city, v_next.public_address, v_next.public_phone, v_next.primary_color, v_next.accent_color,
      v_next.visual_preset, v_next.locale_default, v_next.card_mode, v_next.motion, v_next.pickup_enabled,
      false, false, v_next.paused_until, v_next.pause_reason, v_next.opening_hours, v_next.logo_media_id,
      v_next.hero_media_id, v_next.is_published, v_new_version);
  end if;
  select to_jsonb(p) into v_new from public.restaurant_storefront_profiles p where p.restaurant_id = p_restaurant_id;
  perform app.management_audit(p_organization_id, p_restaurant_id, null,
    'settings.storefront.updated', v_old, v_new);
  return v_result;
end;
$$;

-- Existing semantics preserved; product associations excluded/protected.
create or replace function app.storefront_content_media_url_v1(p_org uuid,p_restaurant uuid,p_branch uuid,p_media uuid)
returns text language sql stable set search_path='' as $$
 select '/storage/v1/object/public/storefront-media/'||m.object_key
 from public.storefront_media m
 where m.id=p_media and m.organization_id=p_org and m.restaurant_id=p_restaurant
  and m.product_derivative_id is null and m.variant='w960' and m.published_at is not null and m.unpublished_at is null
  and exists(select 1 from storage.objects o where o.bucket_id='storefront-media' and o.name=m.object_key
    and o.metadata->>'mimetype'='image/webp' and o.metadata->>'size'=m.bytes::text)
  and ((m.source_bucket='menu-images' and exists(select 1 from storage.objects o cross join lateral app.menu_image_scope(o.name) s
    where o.bucket_id=m.source_bucket and o.name=m.source_key and s.organization_id=p_org and s.restaurant_id=p_restaurant and (s.branch_id is null or s.branch_id=p_branch)))
   or (m.source_bucket='restaurant-logos' and exists(select 1 from storage.objects o cross join lateral app.restaurant_logo_scope(o.name) s
    where o.bucket_id=m.source_bucket and o.name=m.source_key and s.organization_id=p_org and s.restaurant_id=p_restaurant)));
$$;

-- Existing semantics preserved; product associations excluded/protected.
create or replace function app.storefront_content_media_in_use_v1(p_org uuid,p_restaurant uuid,p_branch uuid,p_media uuid)
returns boolean language sql stable set search_path='' as $$
 select coalesce(exists(select 1 from app.storefront_content_profiles c where c.organization_id=p_org and c.restaurant_id=p_restaurant and c.storefront_branch_id=p_branch and c.deleted_at is null
   and (c.promo_media_id=p_media or c.story_media_id=p_media or c.appearance->>'menu_background_media_id'=p_media::text))
  or exists(select 1 from app.storefront_category_presentation c join app.storefront_content_profiles p using(organization_id,restaurant_id,storefront_branch_id)
   where c.organization_id=p_org and c.restaurant_id=p_restaurant and c.storefront_branch_id=p_branch and c.deleted_at is null and p.deleted_at is null and c.editorial_media_id=p_media) or exists(select 1 from app.storefront_product_selections s join public.storefront_media m on m.product_derivative_id=s.derivative_id
   where s.organization_id=p_org and s.restaurant_id=p_restaurant and m.id=p_media),false);
$$;

create function public.get_storefront_product_original_v1(p_organization_id uuid,p_restaurant_id uuid,p_item_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select app.get_storefront_product_original_v1(p_organization_id,p_restaurant_id,p_item_id); $$;
revoke all on function app.get_storefront_product_original_v1(uuid,uuid,uuid), public.get_storefront_product_original_v1(uuid,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function app.get_storefront_product_original_v1(uuid,uuid,uuid), public.get_storefront_product_original_v1(uuid,uuid,uuid) to authenticated;
alter function app.get_storefront_product_original_v1(uuid,uuid,uuid) owner to postgres;

create function public.register_storefront_product_derivative_v1(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_item_id uuid,p_original_key text,p_original_snapshot jsonb,p_candidate_key text,p_treatment text,p_expected_selection_version bigint) returns jsonb language sql security invoker set search_path='' as $$ select app.register_storefront_product_derivative_v1(p_client_request_id,p_organization_id,p_restaurant_id,p_item_id,p_original_key,p_original_snapshot,p_candidate_key,p_treatment,p_expected_selection_version); $$;
revoke all on function app.register_storefront_product_derivative_v1(uuid,uuid,uuid,uuid,text,jsonb,text,text,bigint), public.register_storefront_product_derivative_v1(uuid,uuid,uuid,uuid,text,jsonb,text,text,bigint) from public,anon,authenticated,service_role;
grant execute on function app.register_storefront_product_derivative_v1(uuid,uuid,uuid,uuid,text,jsonb,text,text,bigint), public.register_storefront_product_derivative_v1(uuid,uuid,uuid,uuid,text,jsonb,text,text,bigint) to authenticated;
alter function app.register_storefront_product_derivative_v1(uuid,uuid,uuid,uuid,text,jsonb,text,text,bigint) owner to postgres;

create function public.get_storefront_product_source_v1(p_organization_id uuid,p_restaurant_id uuid,p_derivative_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select app.get_storefront_product_source_v1(p_organization_id,p_restaurant_id,p_derivative_id); $$;
revoke all on function app.get_storefront_product_source_v1(uuid,uuid,uuid), public.get_storefront_product_source_v1(uuid,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function app.get_storefront_product_source_v1(uuid,uuid,uuid), public.get_storefront_product_source_v1(uuid,uuid,uuid) to authenticated;
alter function app.get_storefront_product_source_v1(uuid,uuid,uuid) owner to postgres;

create function public.stage_storefront_product_media_v1(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_derivative_id uuid,p_source_key text,p_source_snapshot jsonb,p_variant text,p_content_hash text,p_width integer,p_height integer,p_bytes integer) returns jsonb language sql security invoker set search_path='' as $$ select app.stage_storefront_product_media_v1(p_client_request_id,p_organization_id,p_restaurant_id,p_derivative_id,p_source_key,p_source_snapshot,p_variant,p_content_hash,p_width,p_height,p_bytes); $$;
revoke all on function app.stage_storefront_product_media_v1(uuid,uuid,uuid,uuid,text,jsonb,text,text,integer,integer,integer), public.stage_storefront_product_media_v1(uuid,uuid,uuid,uuid,text,jsonb,text,text,integer,integer,integer) from public,anon,authenticated,service_role;
grant execute on function app.stage_storefront_product_media_v1(uuid,uuid,uuid,uuid,text,jsonb,text,text,integer,integer,integer), public.stage_storefront_product_media_v1(uuid,uuid,uuid,uuid,text,jsonb,text,text,integer,integer,integer) to authenticated;
alter function app.stage_storefront_product_media_v1(uuid,uuid,uuid,uuid,text,jsonb,text,text,integer,integer,integer) owner to postgres;

create function public.finalize_storefront_product_media_v1(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_media_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select app.finalize_storefront_product_media_v1(p_client_request_id,p_organization_id,p_restaurant_id,p_media_id); $$;
revoke all on function app.finalize_storefront_product_media_v1(uuid,uuid,uuid,uuid), public.finalize_storefront_product_media_v1(uuid,uuid,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function app.finalize_storefront_product_media_v1(uuid,uuid,uuid,uuid), public.finalize_storefront_product_media_v1(uuid,uuid,uuid,uuid) to authenticated;
alter function app.finalize_storefront_product_media_v1(uuid,uuid,uuid,uuid) owner to postgres;

create function public.select_storefront_product_derivative_v1(p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,p_derivative_id uuid) returns jsonb language sql security invoker set search_path='' as $$ select app.select_storefront_product_derivative_v1(p_client_request_id,p_organization_id,p_restaurant_id,p_derivative_id); $$;
revoke all on function app.select_storefront_product_derivative_v1(uuid,uuid,uuid,uuid), public.select_storefront_product_derivative_v1(uuid,uuid,uuid,uuid) from public,anon,authenticated,service_role;
grant execute on function app.select_storefront_product_derivative_v1(uuid,uuid,uuid,uuid), public.select_storefront_product_derivative_v1(uuid,uuid,uuid,uuid) to authenticated;
alter function app.select_storefront_product_derivative_v1(uuid,uuid,uuid,uuid) owner to postgres;
revoke all on function app.storefront_product_authorize_v1(uuid,uuid) from public,anon,authenticated,service_role;
alter function app.storefront_product_authorize_v1(uuid,uuid) owner to postgres;
revoke all on function app.storefront_product_candidate_snapshot_v1(uuid,uuid,uuid,text,text) from public,anon,authenticated,service_role;
alter function app.storefront_product_candidate_snapshot_v1(uuid,uuid,uuid,text,text) owner to postgres;
revoke all on function app.storefront_product_current_v1(uuid,uuid,uuid) from public,anon,authenticated,service_role;
alter function app.storefront_product_current_v1(uuid,uuid,uuid) owner to postgres;
revoke all on function app.storefront_product_images_v1(uuid,uuid,uuid) from public,anon,authenticated,service_role;
alter function app.storefront_product_images_v1(uuid,uuid,uuid) owner to postgres;

