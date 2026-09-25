-- ============================================================================
-- STOREFRONT-PUBLISH-001 — the storefront media publication write path
-- (Option C: one server-side Edge Function, supabase/functions/
-- storefront-media-publish, derives the WebP with its pinned image recipe and
-- drives these RPCs AS THE CALLER. The recipe id and its engine belong to the
-- function; nothing in this file depends on them.)
--
-- Owner authorisation: "OWNER APPROVED — STOREFRONT-PUBLISH-001 OPTION C FULL
-- LOCAL IMPLEMENTATION" (2026-09-25), corrected under "OWNER APPROVED —
-- STOREFRONT-PUBLISH-001 Q031 REMEDIATION + CORRECTION PASS" (2026-09-25).
-- Sealed plan: worktrees/output/storefront-publish-001-plan-20260924T085908Z
-- (DB_SECURITY_DELTA.md), as amended by the Option C spike
-- (…-media-c-spike-20260924T164159Z) and the owner packets. NOT applied to
-- hosted by this file.
--
-- WHAT THIS FILE ADDS / CHANGES
--   1. storefront_media_live_source_idx: the partial-unique predicate becomes
--      LIVE-only (`published_at is not null and unpublished_at is null`), so a
--      STAGED replacement can coexist with the LIVE row it replaces, and several
--      STAGED attempts of one source may exist.
--   2. app.stage_storefront_media     + public wrapper — register a STAGED row
--   3. app.finalize_storefront_media  + public wrapper — check that the
--      uploaded object's ROW exists with the declared metadata, publish
--      (STAGED/RETRACTED -> LIVE), same-source replacement with an atomic
--      profile re-point
--   4. app.cancel_storefront_media    + public wrapper — delete a STAGED row
--   5. app.retract_storefront_media   + public wrapper — LIVE -> RETRACTED
--   6. app.list_storefront_media      + public wrapper — manager+ listing
--
-- STATE MODEL (public.storefront_media)
--   STAGED    published_at is null                       registered, NOT part of
--             the public data contract: storefront_menu never references it and
--             the profile writer refuses to point at it. The bucket is PUBLIC, so
--             STAGED means "not referenced", not "private": an uploaded object is
--             anonymously fetchable from upload on. Its object name is the content
--             address the stager DECLARED (on the Edge Function path, the sha-256
--             of a derivative only the uploader has).
--   LIVE      published_at set, unpublished_at null      referenceable
--   RETRACTED unpublished_at set                         no longer referenceable;
--             RETRACTED -> LIVE is allowed (finalize again).
--   No path in this ticket deletes a storefront-media OBJECT. cancel deletes a
--   STAGED ROW only (an uploaded object becomes unregistered and is reused by a
--   later stage of the same bytes); retract keeps the object (a CDN copy could
--   not be recalled anyway). Physical purge is a later, separately approved
--   ticket.
--
-- SECURITY POSTURE (D-011 / D-012 / D-013 / D-037 as amended / T-016 / T-017)
--   * Every new public function is a SECURITY INVOKER wrapper over an app.*
--     SECURITY DEFINER body (set search_path = ''). EXECUTE: revoked from PUBLIC
--     and anon, GRANTED to authenticated on BOTH layers (an INVOKER wrapper over
--     an ungranted DEFINER body is 42501 for everyone — the REPORT-123 lesson; the
--     sealed DB_SECURITY_DELTA §3 line 55 had this defect, corrected here).
--   * The anon allowlist stays EXACTLY storefront_menu(text); the public
--     SECURITY DEFINER set stays EXACTLY storefront_menu(text) (asserted below).
--   * Authority: app.actor_rank_in_scope(org, restaurant, null) >= 2 (manager+
--     covering the restaurant); rank 0 (no covering membership, cross-tenant,
--     anonymous) raises 42501 with no state leak; rank 1 is refused with an
--     audited typed permission_denied (list: uniform not_found).
--   * No service-role path: the Edge Function calls these as the USER (caller
--     JWT); finalize reads storage.objects as the function OWNER to check the
--     object ROW the user uploaded (it exists, and its DECLARED metadata says
--     image/webp and exactly the staged size) — the caller never needs a
--     storage.objects privilege it does not already have.
--   * WHAT THE DATABASE DOES NOT PROVE (review DB-1 / DB-2 / STG-1): the
--     finalize check proves only that an object ROW exists under the registered
--     key with the DECLARED metadata. storage.objects.metadata is what the
--     storage API recorded for the upload (the mimetype is declared by the
--     uploader, and the copy route can carry another object's metadata past
--     the bucket's size and type limits — review DB-1), and the database never
--     reads the bytes: it cannot tell that they are WebP, that they hash to the
--     registered content address, or that they came through the canonical
--     recipe (re-encode, metadata strip, variant box, <= 512 KiB). stage takes
--     the content hash, width, height and bytes as the caller's declaration.
--     The canonical recipe is enforced by the Edge Function (the honest
--     client). A manager+ who calls these RPCs and the Storage API directly can
--     therefore publish non-canonical bytes (for example an unstripped
--     original) on THEIR OWN restaurant's storefront; the restaurant-bound
--     prefix, the registration-keyed storage policies and the tenant checks
--     below keep it inside that tenant. Recorded as a residual OPEN QUESTION in
--     docs/OPEN_QUESTIONS.md (owned by docs/SECURITY_AND_THREAT_MODEL.md).
--   * Idempotent per (actor, client_request_id) through the RF-112 management
--     ledger; typed failures are never claimed (a retry re-evaluates). A replay
--     of stage / finalize / retract RE-READS its row: a row gone since is
--     stale_request; stage reports the row's current state; finalize (row no
--     longer LIVE) and retract (row no longer RETRACTED) answer stale_request.
--   * Lock order everywhere: restaurants row FOR UPDATE -> profile row -> media
--     rows (the profile writer already locks restaurant -> profile).
--   * The storage policies of READ-001 are unchanged (registration-keyed; a
--     manager can still act on a registered object of their own restaurant
--     through the raw Storage API — documented residual, sealed plan R5 /
--     OPEN QUESTION Q-033).
--   * Item images stay OUT: stage refuses the (menu-images, w480) combination
--     that public.storefront_menu joins for item image_url.
--
-- Money: none. No float anywhere (D-007).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. The live-source index: LIVE rows only.
-- ----------------------------------------------------------------------------
drop index if exists public.storefront_media_live_source_idx;
create unique index storefront_media_live_source_idx
  on public.storefront_media (organization_id, restaurant_id, source_bucket, source_key, variant)
  where published_at is not null and unpublished_at is null;

comment on index public.storefront_media_live_source_idx is
  'STOREFRONT-PUBLISH-001: at most ONE LIVE derivative per (restaurant, source, variant). STAGED (published_at null) and RETRACTED rows are outside the predicate, so a replacement can be staged next to the LIVE row it replaces; finalize retracts the old row before publishing the new one.';

-- ----------------------------------------------------------------------------
-- 2. app.stage_storefront_media — register (or find) the derivative of ONE
--    private original for ONE variant, BEFORE its object is uploaded (the
--    storage INSERT policy requires a registered key).
-- ----------------------------------------------------------------------------
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
  p_bytes             integer
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
  -- (menu-images, w480) is the ITEM image slot public.storefront_menu joins: out of scope here.
  if p_source_bucket = 'menu-images' and p_variant = 'w480' then
    return jsonb_build_object('ok', false, 'error', 'invalid', 'reason', 'variant_not_allowed', 'entity', c_entity);
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
  v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id,
              'bucket', p_source_bucket, 'key', p_source_key, 'variant', p_variant,
              'hash', p_content_hash, 'width', p_width, 'height', p_height, 'bytes', p_bytes)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'stage_storefront_media', v_fp);
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

  -- (g) one derivative per BYTES per restaurant: the object key is the content address
  v_key := app.storefront_media_prefix(p_restaurant_id) || '/' || p_content_hash || '.webp';
  select * into v_row from public.storefront_media sm where sm.object_key = v_key for update;
  if found then
    if v_row.organization_id <> p_organization_id or v_row.restaurant_id <> p_restaurant_id then
      raise exception 'stage_storefront_media: content address owned by another scope' using errcode = '42501';
    end if;
    -- the same content address with other facts can only come from a dishonest client
    if v_row.width <> p_width or v_row.height <> p_height or v_row.bytes <> p_bytes then
      return jsonb_build_object('ok', false, 'error', 'content_mismatch', 'entity', c_entity);
    end if;
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
                                       object_key, content_hash, width, height, bytes, published_at, unpublished_at)
  values (v_id, p_organization_id, p_restaurant_id, p_source_bucket, p_source_key, p_variant,
          v_key, p_content_hash, p_width, p_height, p_bytes, null, null)
  returning * into v_row;
  perform app.management_audit(p_organization_id, p_restaurant_id, null,
    'settings.storefront.media.staged', null, to_jsonb(v_row));
  return v_result;
end;
$$;

comment on function app.stage_storefront_media(uuid, uuid, uuid, text, text, text, text, integer, integer, integer) is
  'STOREFRONT-PUBLISH-001: registers the public derivative of ONE private original (menu-images / restaurant-logos, proven to exist in storage.objects under THIS org + restaurant) for ONE variant (w480 / w960; menu-images w480 = item images refused as variant_not_allowed) as a STAGED row keyed by its content address <prefix>/<sha256>.webp. The content hash, width, height and bytes are the caller''s declaration (checked for shape and bounds, never against any bytes). An existing row of the same bytes is returned (existing, source_mismatch flags; content_mismatch when its facts differ). Manager+ (rank>=2; rank 1 audited permission_denied; rank 0 / cross-tenant 42501). Idempotent per (actor, client_request_id). Audit settings.storefront.media.staged. Never references anything public.';

create or replace function public.stage_storefront_media(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_source_bucket text, p_source_key text,
  p_variant text, p_content_hash text, p_width integer, p_height integer, p_bytes integer)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.stage_storefront_media(p_client_request_id, p_organization_id, p_restaurant_id, p_source_bucket,
        p_source_key, p_variant, p_content_hash, p_width, p_height, p_bytes); $$;

revoke all on function app.stage_storefront_media(uuid, uuid, uuid, text, text, text, text, integer, integer, integer)    from public;
revoke all on function app.stage_storefront_media(uuid, uuid, uuid, text, text, text, text, integer, integer, integer)    from anon;
grant execute on function app.stage_storefront_media(uuid, uuid, uuid, text, text, text, text, integer, integer, integer) to authenticated;
revoke all on function public.stage_storefront_media(uuid, uuid, uuid, text, text, text, text, integer, integer, integer)    from public;
revoke all on function public.stage_storefront_media(uuid, uuid, uuid, text, text, text, text, integer, integer, integer)    from anon;
grant execute on function public.stage_storefront_media(uuid, uuid, uuid, text, text, text, text, integer, integer, integer) to authenticated;

-- ----------------------------------------------------------------------------
-- 3. app.finalize_storefront_media — check the uploaded object's row, publish.
-- ----------------------------------------------------------------------------
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

comment on function app.finalize_storefront_media(uuid, uuid, uuid, uuid) is
  'STOREFRONT-PUBLISH-001: publishes a STAGED or RETRACTED derivative of THIS restaurant after checking, as the function owner, that an object ROW exists in storefront-media under the registered content address whose DECLARED metadata says mimetype image/webp and exactly the staged size (object_missing / object_mismatch otherwise, not claimed; checked on replays and already-LIVE rows too). The bytes are never read: their format and hash are not verified here (the canonical recipe is enforced by the Edge Function). Same-source replacement: another LIVE row of the same (source, variant) is retracted first and every profile pointer at it moves to this row in the same transaction (profile version + 1; audit settings.storefront.updated reason media_replaced). LIVE already => idempotent ok. Manager+ only; idempotent per (actor, client_request_id); audit settings.storefront.media.published.';

create or replace function public.finalize_storefront_media(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_media_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.finalize_storefront_media(p_client_request_id, p_organization_id, p_restaurant_id, p_media_id); $$;

revoke all on function app.finalize_storefront_media(uuid, uuid, uuid, uuid)    from public;
revoke all on function app.finalize_storefront_media(uuid, uuid, uuid, uuid)    from anon;
grant execute on function app.finalize_storefront_media(uuid, uuid, uuid, uuid) to authenticated;
revoke all on function public.finalize_storefront_media(uuid, uuid, uuid, uuid)    from public;
revoke all on function public.finalize_storefront_media(uuid, uuid, uuid, uuid)    from anon;
grant execute on function public.finalize_storefront_media(uuid, uuid, uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 4. app.cancel_storefront_media — delete a STAGED row (never an object).
-- ----------------------------------------------------------------------------
create or replace function app.cancel_storefront_media(
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
  v_actor  uuid := app.current_app_user_id();
  v_rank   integer;
  v_fp     text;
  v_replay jsonb;
  v_result jsonb;
  v_row    public.storefront_media%rowtype;
  c_entity constant text := 'storefront_media';
begin
  if v_actor is null then
    raise exception 'cancel_storefront_media: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null or p_organization_id is null or p_restaurant_id is null or p_media_id is null then
    raise exception 'cancel_storefront_media: client_request_id, organization_id, restaurant_id and media_id are required' using errcode = '42501';
  end if;
  -- the restaurant must belong to the organization BEFORE any authority branch: a foreign or
  -- unknown restaurant raises like rank 0 (no typed answer, no audit row under a foreign id)
  if not exists (select 1 from public.restaurants r
                  where r.id = p_restaurant_id and r.organization_id = p_organization_id and r.deleted_at is null) then
    raise exception 'cancel_storefront_media: restaurant not found in organization or soft-deleted' using errcode = '42501';
  end if;
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, null);
  if v_rank = 0 then
    raise exception 'cancel_storefront_media: caller has no active membership covering the restaurant' using errcode = '42501';
  end if;
  if v_rank < 2 then
    perform app.management_audit(p_organization_id, p_restaurant_id, null,
      'settings.storefront.media.denied', null,
      jsonb_build_object('restaurant_id', p_restaurant_id, 'operation', 'cancel'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', c_entity);
  end if;
  perform 1 from public.restaurants r
   where r.id = p_restaurant_id and r.organization_id = p_organization_id and r.deleted_at is null
   for update;
  if not found then
    raise exception 'cancel_storefront_media: restaurant not found in organization or soft-deleted' using errcode = '42501';
  end if;

  v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id, 'media', p_media_id)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'cancel_storefront_media', v_fp);
  if v_replay is not null then
    return v_replay;
  end if;

  select * into v_row from public.storefront_media sm
   where sm.id = p_media_id and sm.organization_id = p_organization_id and sm.restaurant_id = p_restaurant_id
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', c_entity);
  end if;
  if v_row.published_at is not null then
    -- LIVE or RETRACTED: its object may be (or have been) public; never discarded here
    return jsonb_build_object('ok', false, 'error', 'media_published', 'entity', c_entity);
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', c_entity,
    'media_id', v_row.id, 'state', 'cancelled');
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'cancel_storefront_media', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;
  delete from public.storefront_media where id = v_row.id;
  perform app.management_audit(p_organization_id, p_restaurant_id, null,
    'settings.storefront.media.cancelled', to_jsonb(v_row), null);
  return v_result;
end;
$$;

comment on function app.cancel_storefront_media(uuid, uuid, uuid, uuid) is
  'STOREFRONT-PUBLISH-001: discards a STAGED storefront_media ROW of THIS restaurant (recovery of an abandoned publish). Never deletes an object: an already-uploaded object stays unregistered at its content address and is reused by a later stage of the same bytes. LIVE / RETRACTED => media_published. Manager+ only; idempotent per (actor, client_request_id); audit settings.storefront.media.cancelled.';

create or replace function public.cancel_storefront_media(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_media_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.cancel_storefront_media(p_client_request_id, p_organization_id, p_restaurant_id, p_media_id); $$;

revoke all on function app.cancel_storefront_media(uuid, uuid, uuid, uuid)    from public;
revoke all on function app.cancel_storefront_media(uuid, uuid, uuid, uuid)    from anon;
grant execute on function app.cancel_storefront_media(uuid, uuid, uuid, uuid) to authenticated;
revoke all on function public.cancel_storefront_media(uuid, uuid, uuid, uuid)    from public;
revoke all on function public.cancel_storefront_media(uuid, uuid, uuid, uuid)    from anon;
grant execute on function public.cancel_storefront_media(uuid, uuid, uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 5. app.retract_storefront_media — LIVE -> RETRACTED (the object is kept).
-- ----------------------------------------------------------------------------
create or replace function app.retract_storefront_media(
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
  v_actor    uuid := app.current_app_user_id();
  v_rank     integer;
  v_fp       text;
  v_replay   jsonb;
  v_result   jsonb;
  v_row      public.storefront_media%rowtype;
  v_before   jsonb;
  v_prof     public.restaurant_storefront_profiles%rowtype;
  v_has_prof boolean;
  v_slots    text[] := '{}';
  c_entity constant text := 'storefront_media';
begin
  if v_actor is null then
    raise exception 'retract_storefront_media: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null or p_organization_id is null or p_restaurant_id is null or p_media_id is null then
    raise exception 'retract_storefront_media: client_request_id, organization_id, restaurant_id and media_id are required' using errcode = '42501';
  end if;
  -- the restaurant must belong to the organization BEFORE any authority branch: a foreign or
  -- unknown restaurant raises like rank 0 (no typed answer, no audit row under a foreign id)
  if not exists (select 1 from public.restaurants r
                  where r.id = p_restaurant_id and r.organization_id = p_organization_id and r.deleted_at is null) then
    raise exception 'retract_storefront_media: restaurant not found in organization or soft-deleted' using errcode = '42501';
  end if;
  v_rank := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, null);
  if v_rank = 0 then
    raise exception 'retract_storefront_media: caller has no active membership covering the restaurant' using errcode = '42501';
  end if;
  if v_rank < 2 then
    perform app.management_audit(p_organization_id, p_restaurant_id, null,
      'settings.storefront.media.denied', null,
      jsonb_build_object('restaurant_id', p_restaurant_id, 'operation', 'retract'));
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', c_entity);
  end if;
  perform 1 from public.restaurants r
   where r.id = p_restaurant_id and r.organization_id = p_organization_id and r.deleted_at is null
   for update;
  if not found then
    raise exception 'retract_storefront_media: restaurant not found in organization or soft-deleted' using errcode = '42501';
  end if;
  select * into v_prof from public.restaurant_storefront_profiles p
   where p.restaurant_id = p_restaurant_id and p.organization_id = p_organization_id and p.deleted_at is null
   for update;
  v_has_prof := found;

  v_fp := md5(jsonb_build_object('org', p_organization_id, 'restaurant', p_restaurant_id, 'media', p_media_id)::text);
  v_replay := app.management_idem_check(v_actor, p_client_request_id, 'retract_storefront_media', v_fp);

  -- A REPLAY re-reads its row too (as the stage and finalize replays do): the stored answer is
  -- always "retracted", so a row gone since, or LIVE again since (RETRACTED -> LIVE through a
  -- later finalize), makes that answer stale -- the caller must look again (list) or retract
  -- with a new request, never be told "retracted" for a publicly referenceable row. Not claimed.
  select * into v_row from public.storefront_media sm
   where sm.id = p_media_id and sm.organization_id = p_organization_id and sm.restaurant_id = p_restaurant_id
   for update;
  if not found then
    return jsonb_build_object('ok', false, 'error', case when v_replay is null then 'not_found' else 'stale_request' end, 'entity', c_entity);
  end if;
  if v_replay is not null then
    if v_row.published_at is not null and v_row.unpublished_at is not null then
      return v_replay;   -- still RETRACTED: the stored answer holds
    end if;
    return jsonb_build_object('ok', false, 'error', 'stale_request', 'entity', c_entity);
  end if;
  if v_row.published_at is null then
    return jsonb_build_object('ok', false, 'error', 'media_not_published', 'entity', c_entity);
  end if;
  if v_row.unpublished_at is not null then
    v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', c_entity,
      'media_id', v_row.id, 'state', 'retracted', 'already_retracted', true);
    v_replay := app.management_claim_request(v_actor, p_client_request_id, 'retract_storefront_media', v_fp, v_result);
    return coalesce(v_replay, v_result);
  end if;
  if v_has_prof then
    if v_prof.logo_media_id = v_row.id then v_slots := v_slots || 'logo'::text; end if;
    if v_prof.hero_media_id = v_row.id then v_slots := v_slots || 'hero'::text; end if;
  end if;
  if coalesce(array_length(v_slots, 1), 0) > 0 then
    return jsonb_build_object('ok', false, 'error', 'media_in_use', 'slots', to_jsonb(v_slots), 'entity', c_entity);
  end if;

  v_result := jsonb_build_object('ok', true, 'idempotent_replay', false, 'entity', c_entity,
    'media_id', v_row.id, 'state', 'retracted', 'already_retracted', false);
  v_replay := app.management_claim_request(v_actor, p_client_request_id, 'retract_storefront_media', v_fp, v_result);
  if v_replay is not null then
    return v_replay;
  end if;
  v_before := to_jsonb(v_row);
  update public.storefront_media
     set unpublished_at = greatest(now(), published_at)
   where id = v_row.id
   returning * into v_row;
  perform app.management_audit(p_organization_id, p_restaurant_id, null,
    'settings.storefront.media.retracted', v_before, to_jsonb(v_row));
  return v_result;
end;
$$;

comment on function app.retract_storefront_media(uuid, uuid, uuid, uuid) is
  'STOREFRONT-PUBLISH-001: LIVE -> RETRACTED for a derivative of THIS restaurant: public.storefront_menu stops referencing it at once. Refused with media_in_use (+ slots) while the profile points at it (clear or replace the slot first); STAGED => media_not_published (use cancel); RETRACTED => idempotent ok. A replay re-reads its row: gone or LIVE again since (re-published) => stale_request (not claimed); still RETRACTED => the stored answer. The object is kept (a CDN copy cannot be recalled; purge is a later ticket); RETRACTED -> LIVE via finalize. Manager+ only; idempotent per (actor, client_request_id); audit settings.storefront.media.retracted.';

create or replace function public.retract_storefront_media(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_media_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.retract_storefront_media(p_client_request_id, p_organization_id, p_restaurant_id, p_media_id); $$;

revoke all on function app.retract_storefront_media(uuid, uuid, uuid, uuid)    from public;
revoke all on function app.retract_storefront_media(uuid, uuid, uuid, uuid)    from anon;
grant execute on function app.retract_storefront_media(uuid, uuid, uuid, uuid) to authenticated;
revoke all on function public.retract_storefront_media(uuid, uuid, uuid, uuid)    from public;
revoke all on function public.retract_storefront_media(uuid, uuid, uuid, uuid)    from anon;
grant execute on function public.retract_storefront_media(uuid, uuid, uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 6. app.list_storefront_media — manager+ listing (the Dashboard's
--    authoritative state after any unknown outcome).
-- ----------------------------------------------------------------------------
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
       order by sm.created_at desc, sm.id
       limit 200
    ) x;
  return jsonb_build_object('ok', true, 'entity', c_entity, 'restaurant_id', p_restaurant_id,
    'media_prefix', app.storefront_media_prefix(p_restaurant_id), 'media', v_media);
end;
$$;

comment on function app.list_storefront_media(uuid, uuid) is
  'STOREFRONT-PUBLISH-001: the storefront derivatives of THIS restaurant (newest first, at most 200) with their state (staged / published / retracted), private source key, facts and the profile slots using them, plus the opaque media prefix. Manager+ covering the restaurant; below-manager, cross-tenant and unknown all return not_found (no leak). The Dashboard''s authoritative refresh after any unknown outcome.';

create or replace function public.list_storefront_media(p_organization_id uuid, p_restaurant_id uuid)
  returns jsonb language sql stable security invoker set search_path = ''
as $$ select app.list_storefront_media(p_organization_id, p_restaurant_id); $$;

revoke all on function app.list_storefront_media(uuid, uuid)    from public;
revoke all on function app.list_storefront_media(uuid, uuid)    from anon;
grant execute on function app.list_storefront_media(uuid, uuid) to authenticated;
revoke all on function public.list_storefront_media(uuid, uuid)    from public;
revoke all on function public.list_storefront_media(uuid, uuid)    from anon;
grant execute on function public.list_storefront_media(uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 7. Assert the posture this file establishes; abort the transaction otherwise.
-- ----------------------------------------------------------------------------
do $$
declare
  v_anon_set text;
  v_defs     text;
  v_fn       text;
  v_idx      text;
begin
  select coalesce(string_agg(regexp_replace(p.oid::regprocedure::text, '^public.', ''), ', ' order by regexp_replace(p.oid::regprocedure::text, '^public.', '')), '')
    into v_anon_set
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
     and has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_anon_set <> 'storefront_menu(text)' then
    raise exception 'STOREFRONT-PUBLISH-001 posture NOT reached: anon-executable public set is [%], expected exactly storefront_menu(text)', v_anon_set;
  end if;
  select coalesce(string_agg(regexp_replace(p.oid::regprocedure::text, '^public.', ''), ', ' order by regexp_replace(p.oid::regprocedure::text, '^public.', '')), '')
    into v_defs
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') and p.prosecdef;
  if v_defs <> 'storefront_menu(text)' then
    raise exception 'STOREFRONT-PUBLISH-001 posture NOT reached: public SECURITY DEFINER set is [%], expected exactly storefront_menu(text)', v_defs;
  end if;
  foreach v_fn in array array[
    'stage_storefront_media(uuid,uuid,uuid,text,text,text,text,integer,integer,integer)',
    'finalize_storefront_media(uuid,uuid,uuid,uuid)',
    'cancel_storefront_media(uuid,uuid,uuid,uuid)',
    'retract_storefront_media(uuid,uuid,uuid,uuid)',
    'list_storefront_media(uuid,uuid)']
  loop
    if not has_function_privilege('authenticated', ('public.' || v_fn)::regprocedure, 'EXECUTE')
       or not has_function_privilege('authenticated', ('app.' || v_fn)::regprocedure, 'EXECUTE') then
      raise exception 'STOREFRONT-PUBLISH-001 posture NOT reached: authenticated cannot EXECUTE % on both layers', v_fn;
    end if;
    if has_function_privilege('anon', ('public.' || v_fn)::regprocedure, 'EXECUTE')
       or has_function_privilege('anon', ('app.' || v_fn)::regprocedure, 'EXECUTE') then
      raise exception 'STOREFRONT-PUBLISH-001 posture NOT reached: anon can EXECUTE %', v_fn;
    end if;
    if (select prosecdef from pg_proc where oid = ('public.' || v_fn)::regprocedure)
       or not (select prosecdef from pg_proc where oid = ('app.' || v_fn)::regprocedure) then
      raise exception 'STOREFRONT-PUBLISH-001 posture NOT reached: % must be INVOKER (public) over DEFINER (app)', v_fn;
    end if;
  end loop;
  select indexdef into v_idx from pg_indexes
   where schemaname = 'public' and indexname = 'storefront_media_live_source_idx';
  if v_idx is null or v_idx !~ 'WHERE \(\(published_at IS NOT NULL\) AND \(unpublished_at IS NULL\)\)' then
    raise exception 'STOREFRONT-PUBLISH-001 posture NOT reached: live-source index predicate is [%]', v_idx;
  end if;
  if has_schema_privilege('anon', 'app', 'USAGE') then
    raise exception 'STOREFRONT-PUBLISH-001 invariant broken: anon has USAGE on schema app';
  end if;
  raise notice 'STOREFRONT-PUBLISH-001 posture reached: anon allowlist = {storefront_menu(text)}, public DEFINER set = {storefront_menu(text)}, 5 media RPCs authenticated-only on both layers, LIVE-only live-source index';
end
$$;

-- ----------------------------------------------------------------------------
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists public.list_storefront_media(uuid, uuid);
--   drop function if exists app.list_storefront_media(uuid, uuid);
--   drop function if exists public.retract_storefront_media(uuid, uuid, uuid, uuid);
--   drop function if exists app.retract_storefront_media(uuid, uuid, uuid, uuid);
--   drop function if exists public.cancel_storefront_media(uuid, uuid, uuid, uuid);
--   drop function if exists app.cancel_storefront_media(uuid, uuid, uuid, uuid);
--   drop function if exists public.finalize_storefront_media(uuid, uuid, uuid, uuid);
--   drop function if exists app.finalize_storefront_media(uuid, uuid, uuid, uuid);
--   drop function if exists public.stage_storefront_media(uuid, uuid, uuid, text, text, text, text, integer, integer, integer);
--   drop function if exists app.stage_storefront_media(uuid, uuid, uuid, text, text, text, text, integer, integer, integer);
--   drop index if exists public.storefront_media_live_source_idx;
--   create unique index storefront_media_live_source_idx on public.storefront_media
--     (organization_id, restaurant_id, source_bucket, source_key, variant) where unpublished_at is null;
--     -- (only valid while at most one non-retracted row exists per source + variant)
-- ----------------------------------------------------------------------------
