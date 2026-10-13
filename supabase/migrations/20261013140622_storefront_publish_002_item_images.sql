-- STOREFRONT-PUBLISH-002: publish current menu-item originals through the
-- existing content-addressed derivative pipeline. No storage object mutation.
-- Legacy logo/hero publication, profile wiring, role floor, audits and public
-- reader payload stay unchanged. Old item rows have no provable source token
-- and fail closed until republished; snapshots are never backfilled by guess.
begin;

alter table public.storefront_media add column item_source_snapshot jsonb;
comment on column public.storefront_media.item_source_snapshot is
  'STOREFRONT-PUBLISH-002: private storage generation captured before download and checked at stage/finalize/read for menu-images w480 only; never exposed by storefront_menu.';
alter table public.storefront_media add constraint storefront_media_item_snapshot_shape check (
  item_source_snapshot is null or (
    source_bucket = 'menu-images' and variant = 'w480'
    and jsonb_typeof(item_source_snapshot) = 'object'
  )
);
alter table public.storefront_media drop constraint storefront_media_object_key_key;
create unique index storefront_media_legacy_object_key_idx
  on public.storefront_media (object_key)
  where not (source_bucket = 'menu-images' and variant = 'w480');
create unique index storefront_media_item_generation_idx
  on public.storefront_media (object_key, source_key, item_source_snapshot)
  where source_bucket = 'menu-images' and variant = 'w480' and item_source_snapshot is not null;

-- Internal, non-callable by app roles. The source must name THIS current live
-- menu item and the item's exact branch scope; merely parsing a tenant prefix
-- or finding a leftover upload does not establish an item association.
create or replace function app.storefront_item_source_snapshot(
  p_organization_id uuid, p_restaurant_id uuid, p_source_key text
)
  returns jsonb
  language sql
  stable
  security invoker
  set search_path = ''
as $$
  select jsonb_build_object(
    'storage_object_id', o.id,
    'storage_version', o.version,
    'storage_updated_at', to_char(o.updated_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))
    from storage.objects o
    cross join lateral app.menu_image_scope(o.name) s
    join public.menu_items i
      on i.organization_id = s.organization_id and i.restaurant_id = s.restaurant_id
     and i.id = s.menu_item_id and i.branch_id is not distinct from s.branch_id
     and i.image_path = o.name and i.deleted_at is null and i.is_active
   where o.bucket_id = 'menu-images' and o.name = p_source_key
     and o.id is not null and o.updated_at is not null
     and s.organization_id = p_organization_id and s.restaurant_id = p_restaurant_id;
$$;
revoke all on function app.storefront_item_source_snapshot(uuid, uuid, text) from public, anon, authenticated;
alter function app.storefront_item_source_snapshot(uuid, uuid, text) owner to postgres;

create or replace function app.get_storefront_item_source(
  p_organization_id uuid, p_restaurant_id uuid, p_source_key text
)
  returns jsonb
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_actor uuid := app.current_app_user_id();
  v_rank integer;
  v_snapshot jsonb;
begin
  if v_actor is null or p_organization_id is null or p_restaurant_id is null then
    raise exception 'get_storefront_item_source: authentication and scope required' using errcode = '42501';
  end if;
  if not exists (select 1 from public.restaurants r where r.id = p_restaurant_id
                  and r.organization_id = p_organization_id and r.deleted_at is null) then
    raise exception 'get_storefront_item_source: restaurant not found in organization or soft-deleted' using errcode = '42501';
  end if;
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, null);
  if v_rank = 0 then
    raise exception 'get_storefront_item_source: caller has no active membership covering the restaurant' using errcode = '42501';
  end if;
  if v_rank < 2 then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'storefront_media');
  end if;
  v_snapshot := app.storefront_item_source_snapshot(p_organization_id, p_restaurant_id, p_source_key);
  if v_snapshot is null then
    return jsonb_build_object('ok', false, 'error', 'source_not_found', 'entity', 'storefront_media');
  end if;
  return jsonb_build_object('ok', true, 'entity', 'storefront_media', 'source_snapshot', v_snapshot);
end;
$$;
create or replace function public.get_storefront_item_source(
  p_organization_id uuid, p_restaurant_id uuid, p_source_key text
)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.get_storefront_item_source(p_organization_id, p_restaurant_id, p_source_key); $$;
revoke all on function app.get_storefront_item_source(uuid, uuid, text) from public, anon;
revoke all on function public.get_storefront_item_source(uuid, uuid, text) from public, anon;
grant execute on function app.get_storefront_item_source(uuid, uuid, text) to authenticated;
grant execute on function public.get_storefront_item_source(uuid, uuid, text) to authenticated;
alter function app.get_storefront_item_source(uuid, uuid, text) owner to postgres;
comment on function public.get_storefront_item_source(uuid, uuid, text) is
  'STOREFRONT-PUBLISH-002: manager-only current-item/private-source generation preflight BEFORE Edge downloads; returns an opaque source_snapshot for stage. Not a public-reader surface.';

-- Replace, rather than overload, both layers. Existing ten-argument logo/hero
-- callers resolve the new optional final argument without PostgREST ambiguity.
drop function public.stage_storefront_media(uuid, uuid, uuid, text, text, text, text, integer, integer, integer);
drop function app.stage_storefront_media(uuid, uuid, uuid, text, text, text, text, integer, integer, integer);

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
   where sm.object_key = v_key
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

create or replace function public.stage_storefront_media(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid,
  p_source_bucket text, p_source_key text, p_variant text, p_content_hash text,
  p_width integer, p_height integer, p_bytes integer, p_source_snapshot jsonb default null
)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.stage_storefront_media(p_client_request_id, p_organization_id, p_restaurant_id,
  p_source_bucket, p_source_key, p_variant, p_content_hash, p_width, p_height, p_bytes, p_source_snapshot); $$;
revoke all on function app.stage_storefront_media(uuid, uuid, uuid, text, text, text, text, integer, integer, integer, jsonb) from public, anon;
revoke all on function public.stage_storefront_media(uuid, uuid, uuid, text, text, text, text, integer, integer, integer, jsonb) from public, anon;
grant execute on function app.stage_storefront_media(uuid, uuid, uuid, text, text, text, text, integer, integer, integer, jsonb) to authenticated;
grant execute on function public.stage_storefront_media(uuid, uuid, uuid, text, text, text, text, integer, integer, integer, jsonb) to authenticated;
alter function app.stage_storefront_media(uuid, uuid, uuid, text, text, text, text, integer, integer, integer, jsonb) owner to postgres;
comment on function app.stage_storefront_media(uuid, uuid, uuid, text, text, text, text, integer, integer, integer, jsonb) is
  'STOREFRONT-PUBLISH-002: legacy logo/hero behavior retained; item w480 requires pre-download current-source snapshot, rechecks freshness including replay, and keeps an independent per-source/generation association when public bytes are shared.';

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
     and sm.source_bucket = v_row.source_bucket and sm.source_key = v_row.source_key and sm.variant = v_row.variant
     and sm.id <> v_row.id and sm.published_at is not null and sm.unpublished_at is null
   for update;
  v_has_old := found;
  if v_has_old and v_has_prof and (v_prof.logo_media_id = v_old.id or v_prof.hero_media_id = v_old.id) then
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

create or replace function public.storefront_menu(p_slug text)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  c_not_found   constant jsonb := jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'storefront_menu');
  c_media_base  constant text  := '/storage/v1/object/public/storefront-media/';
  c_cap_cat     constant integer := 100;
  c_cap_item    constant integer := 500;
  c_cap_mod     constant integer := 2000;
  c_cap_opt     constant integer := 8000;
  v_now         timestamptz := now();
  v_p           record;
  v_hours       record;
  v_state       text;
  v_categories  jsonb;
  v_items       jsonb;
  v_modifiers   jsonb;
  v_options     jsonb;
  v_logo        text;
  v_hero        text;
  v_max_updated timestamptz;
  v_menu_version text;
begin
  -- (a) request grammar (the UI trust boundary); anything else is not_found
  if p_slug is null or p_slug !~ '^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$' then
    return c_not_found;
  end if;

  -- (b) resolve the published profile + the live ancestry (P0), scope derived
  --     ONCE here; no id ever leaves this function
  select p.restaurant_id, p.organization_id, p.storefront_branch_id, p.slug, p.display_name, p.tagline,
         p.public_city, p.public_address, p.public_phone, p.primary_color, p.accent_color, p.visual_preset,
         p.locale_default, p.card_mode, p.motion, p.pickup_enabled, p.paused_until, p.opening_hours,
         p.logo_media_id, p.hero_media_id, p.is_published, p.version, p.updated_at,
         o.status as o_status, o.deleted_at as o_deleted,
         r.status as r_status, r.deleted_at as r_deleted,
         b.status as b_status, b.deleted_at as b_deleted,
         coalesce(b.timezone, r.timezone) as tz,
         coalesce(r.currency_override, o.default_currency) as currency,
         b.tax_enabled, b.tax_rate_bp, b.tax_mode
    into v_p
    from public.restaurant_storefront_profiles p
    join public.restaurants   r on r.id = p.restaurant_id and r.organization_id = p.organization_id
    join public.organizations o on o.id = p.organization_id
    join public.branches      b on b.id = p.storefront_branch_id
                               and b.organization_id = p.organization_id
                               and b.restaurant_id = p.restaurant_id
   where p.slug = p_slug
     and p.deleted_at is null;
  if not found then
    return c_not_found;
  end if;
  if not v_p.is_published
     or v_p.o_status <> 'active' or v_p.o_deleted is not null
     or v_p.r_status <> 'active' or v_p.r_deleted is not null
     or v_p.b_status <> 'active' or v_p.b_deleted is not null
     or v_p.tz is null
     or v_p.currency is distinct from 'ILS'
     or (v_p.tax_enabled and v_p.tax_mode <> 'exclusive') then
    return c_not_found;
  end if;

  -- (c) hours in the branch timezone; an unresolvable zone is a P0 failure
  begin
    select * into v_hours from app.storefront_service_window(v_p.opening_hours, v_p.tz, v_now);
  exception when invalid_parameter_value or invalid_datetime_format then
    return c_not_found;
  end;
  v_state := case
               when v_p.paused_until is not null and v_p.paused_until > v_now then 'paused'
               when v_hours.open_now then 'open'
               else 'closed'
             end;

  -- (d) published media only; never the private key, never a UUID
  select c_media_base || sm.object_key into v_logo
    from public.storefront_media sm
   where sm.id = v_p.logo_media_id and sm.organization_id = v_p.organization_id and sm.restaurant_id = v_p.restaurant_id
     and sm.published_at is not null and sm.unpublished_at is null;
  select c_media_base || sm.object_key into v_hero
    from public.storefront_media sm
   where sm.id = v_p.hero_media_id and sm.organization_id = v_p.organization_id and sm.restaurant_id = v_p.restaurant_id
     and sm.published_at is not null and sm.unpublished_at is null;

  -- (e) live categories of the restaurant, branch-visible (kiosk_menu (d) VERBATIM)
  select coalesce(jsonb_agg(
           jsonb_build_object('id', c.id, 'name', left(c.name, 80), 'display_order', c.display_order,
                              'icon_key', c.icon_key)
           order by c.display_order, c.name), '[]'::jsonb),
         max(c.updated_at)
    into v_categories, v_max_updated
    from public.menu_categories c
   where c.organization_id = v_p.organization_id
     and c.restaurant_id = v_p.restaurant_id
     and c.is_active
     and c.deleted_at is null
     and (c.branch_id is null or c.branch_id = v_p.storefront_branch_id);

  -- (f) live items with the pos_menu / kiosk_menu (e) predicates VERBATIM;
  --     customer-narrow keys; sold-out from the branch availability override;
  --     image_url only from a PUBLISHED derivative of the item's private key
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', i.id, 'category_id', i.menu_category_id, 'name', left(i.name, 120),
             'description', left(coalesce(i.description, ''), 600),
             'base_price_minor', i.base_price_minor, 'display_order', i.display_order,
             -- vocabulary-filtered AND de-duplicated (so at most four values can ever be served),
             -- keeping the tenant's first-occurrence order
             'tags', coalesce((select jsonb_agg(d.t order by d.ord)
                                 from (select x.t, min(x.ord) as ord
                                         from jsonb_array_elements_text(coalesce(i.tags, '[]'::jsonb)) with ordinality as x(t, ord)
                                        where x.t in ('spicy', 'vegetarian', 'popular', 'new')
                                        group by x.t) d), '[]'::jsonb),
             'image_url', case when sm.object_key is null then null else c_media_base || sm.object_key end,
             'availability', coalesce(a.availability, 'available'))
           order by i.display_order, i.name), '[]'::jsonb),
         greatest(v_max_updated, max(i.updated_at))
    into v_items, v_max_updated
    from public.menu_items i
    join public.menu_categories c
      on c.organization_id = i.organization_id
     and c.restaurant_id   = v_p.restaurant_id
     and c.id = i.menu_category_id
    left join public.menu_item_branch_availability a
      on a.organization_id = i.organization_id
     and a.branch_id       = v_p.storefront_branch_id
     and a.menu_item_id    = i.id
    left join public.storefront_media sm
      on sm.organization_id = i.organization_id
     and sm.restaurant_id   = v_p.restaurant_id
     and sm.source_bucket   = 'menu-images'
     and sm.source_key      = i.image_path
     and sm.variant         = 'w480'
     and exists (select 1 from app.menu_image_scope(sm.source_key) item_source
                  where item_source.menu_item_id = i.id
                    and item_source.branch_id is not distinct from i.branch_id)
     and sm.item_source_snapshot = app.storefront_item_source_snapshot(
           i.organization_id, i.restaurant_id, i.image_path)
     and exists (select 1 from storage.objects derivative
                  where derivative.bucket_id = 'storefront-media' and derivative.name = sm.object_key
                    and derivative.metadata ->> 'mimetype' = 'image/webp'
                    and derivative.metadata ->> 'size' = sm.bytes::text)
     and sm.published_at is not null
     and sm.unpublished_at is null
   where i.organization_id = v_p.organization_id
     and i.restaurant_id = v_p.restaurant_id
     and i.is_active
     and i.deleted_at is null
     and (i.branch_id is null or i.branch_id = v_p.storefront_branch_id)
     and c.is_active
     and c.deleted_at is null
     and (c.branch_id is null or c.branch_id = v_p.storefront_branch_id);

  -- (g) live modifiers of LIVE items (kiosk_menu (h) VERBATIM; no quantity keys)
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', m.id, 'item_id', m.menu_item_id, 'name', left(m.name, 80),
             'selection_type', m.selection_type, 'min_select', m.min_select,
             'max_select', m.max_select, 'is_required', m.is_required,
             'display_order', m.display_order)
           order by m.display_order, m.name), '[]'::jsonb),
         greatest(v_max_updated, max(m.updated_at))
    into v_modifiers, v_max_updated
    from public.modifiers m
    join public.menu_items i
      on i.organization_id = m.organization_id
     and i.restaurant_id   = v_p.restaurant_id
     and i.id = m.menu_item_id
    join public.menu_categories c
      on c.organization_id = i.organization_id
     and c.restaurant_id   = v_p.restaurant_id
     and c.id = i.menu_category_id
   where m.organization_id = v_p.organization_id
     and m.restaurant_id = v_p.restaurant_id
     and m.is_active
     and m.deleted_at is null
     and (m.branch_id is null or m.branch_id = v_p.storefront_branch_id)
     and i.is_active and i.deleted_at is null and (i.branch_id is null or i.branch_id = v_p.storefront_branch_id)
     and c.is_active and c.deleted_at is null and (c.branch_id is null or c.branch_id = v_p.storefront_branch_id);

  -- (h) live options of LIVE modifiers (kiosk_menu (i) VERBATIM); a NEGATIVE
  --     delta is excluded (the Storefront renders a negative delta as
  --     "included"); no kitchen_meat
  select coalesce(jsonb_agg(
           jsonb_build_object(
             'id', mo.id, 'modifier_id', mo.modifier_id, 'name', left(mo.name, 80),
             'price_delta_minor', mo.price_delta_minor, 'display_order', mo.display_order)
           order by mo.display_order, mo.name), '[]'::jsonb),
         greatest(v_max_updated, max(mo.updated_at))
    into v_options, v_max_updated
    from public.modifier_options mo
    join public.modifiers m
      on m.organization_id = mo.organization_id and m.id = mo.modifier_id
    join public.menu_items i
      on i.organization_id = m.organization_id
     and i.restaurant_id   = v_p.restaurant_id
     and i.id = m.menu_item_id
    join public.menu_categories c
      on c.organization_id = i.organization_id
     and c.restaurant_id   = v_p.restaurant_id
     and c.id = i.menu_category_id
   where mo.organization_id = v_p.organization_id
     and mo.restaurant_id = v_p.restaurant_id
     and mo.is_active
     and mo.deleted_at is null
     and mo.price_delta_minor >= 0
     and (mo.branch_id is null or mo.branch_id = v_p.storefront_branch_id)
     and m.is_active and m.deleted_at is null and (m.branch_id is null or m.branch_id = v_p.storefront_branch_id)
     and i.is_active and i.deleted_at is null and (i.branch_id is null or i.branch_id = v_p.storefront_branch_id)
     and c.is_active and c.deleted_at is null and (c.branch_id is null or c.branch_id = v_p.storefront_branch_id);

  -- (i) payload caps: typed, never disguised as not_found
  if jsonb_array_length(v_categories) > c_cap_cat or jsonb_array_length(v_items) > c_cap_item
     or jsonb_array_length(v_modifiers) > c_cap_mod or jsonb_array_length(v_options) > c_cap_opt then
    return jsonb_build_object('ok', false, 'error', 'payload_limit', 'entity', 'storefront_menu');
  end if;

  -- (j) the cart key: profile version + the newest catalog change (availability
  --     flips deliberately excluded so a sold-out toggle does not reset carts)
  v_menu_version := v_p.version::text || '.' ||
                    coalesce(floor(extract(epoch from greatest(v_max_updated, v_p.updated_at)))::bigint::text, '0');

  return jsonb_build_object(
    'ok', true,
    'entity', 'storefront_menu',
    'menu_version', v_menu_version,
    'server_ts', v_now,
    'restaurant', jsonb_build_object(
      'slug', v_p.slug, 'display_name', v_p.display_name, 'tagline', v_p.tagline,
      'city', v_p.public_city, 'address', v_p.public_address, 'phone', v_p.public_phone,
      'primary_color', v_p.primary_color, 'accent_color', v_p.accent_color,
      'logo_url', v_logo, 'hero_url', v_hero,
      'currency_code', v_p.currency, 'locale_default', v_p.locale_default,
      'visual_preset', v_p.visual_preset, 'card_mode', v_p.card_mode, 'motion', v_p.motion),
    'hours', jsonb_build_object(
      'timezone', v_p.tz, 'opens', v_hours.opens, 'closes', v_hours.closes,
      'open_now', v_hours.open_now, 'next_open', v_hours.next_open),
    'service', jsonb_build_object(
      'state', v_state, 'ordering_enabled', false,
      'pickup_enabled', v_p.pickup_enabled, 'delivery_enabled', false),
    'tax', jsonb_build_object('enabled', v_p.tax_enabled, 'rate_bp', v_p.tax_rate_bp, 'mode', v_p.tax_mode),
    'categories', v_categories,
    'items', v_items,
    'modifiers', v_modifiers,
    'modifier_options', v_options);
end;
$$;

-- An item publication is never a profile logo/hero selection.
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

-- Preserve the profile manager's original newest-200 budget. Item publishes
-- reconcile through their request results, so they must not evict logo/hero
-- history from this existing profile-management list.
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
         and not (sm.source_bucket = 'menu-images' and sm.variant = 'w480')
       order by sm.created_at desc, sm.id
       limit 200
    ) x;
  return jsonb_build_object('ok', true, 'entity', c_entity, 'restaurant_id', p_restaurant_id,
    'media_prefix', app.storefront_media_prefix(p_restaurant_id), 'media', v_media);
end;
$$;
comment on function app.list_storefront_media(uuid, uuid) is
  'STOREFRONT-PUBLISH-002: manager-only profile media list, newest 200 legacy logo/hero rows; item w480 associations excluded before ordering/limit. Existing fields, in_use slots, grants and uniform not_found behavior unchanged.';

commit;
