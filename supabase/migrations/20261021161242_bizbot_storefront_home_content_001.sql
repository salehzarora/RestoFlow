-- BIZBOT-STOREFRONT-HOME-CONTENT-001: bounded merchant-authored Home copy.
-- Additive only. Existing profile writer, menu RPC and operational gates stay intact.
begin;

alter table public.restaurant_storefront_profiles
  add column hero_headline text,
  add column hero_subline text,
  add column announcement_text text,
  add constraint restaurant_storefront_profiles_hero_headline check (
    hero_headline is null or (char_length(hero_headline) between 1 and 120
      and hero_headline !~ '[\x01-\x1f\x7f]'
      and hero_headline = btrim(hero_headline, U&'\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'))),
  add constraint restaurant_storefront_profiles_hero_subline check (
    hero_subline is null or (char_length(hero_subline) between 1 and 180
      and hero_subline !~ '[\x01-\x1f\x7f]'
      and hero_subline = btrim(hero_subline, U&'\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF'))),
  add constraint restaurant_storefront_profiles_announcement_text check (
    announcement_text is null or (char_length(announcement_text) between 1 and 240
      and announcement_text !~ '[\x01-\x1f\x7f]'
      and announcement_text = btrim(announcement_text, U&'\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF')));

-- U+0000 cannot occur in PostgreSQL text/jsonb. Reject other ASCII controls
-- BEFORE trimming; whitespace normalization must not conceal invalid input.
create function app.set_restaurant_storefront_home_content(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid,
  p_expected_version integer, p_patch jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare
  v_actor uuid := app.current_app_user_id();
  v_rank integer;
  v_profile public.restaurant_storefront_profiles%rowtype;
  v_old jsonb;
  v_new jsonb;
  v_key text;
  v_value jsonb;
  v_text text;
  v_normalized jsonb := '{}'::jsonb;
  v_fingerprint text;
  v_replay jsonb;
  v_result jsonb;
  v_limit integer;
  c_entity constant text := 'restaurant_storefront_profile';
  c_operation constant text := 'set_restaurant_storefront_home_content';
  c_fields constant text[] := array['hero_headline','hero_subline','announcement_text'];
  c_trim constant text := U&'\0020\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\2028\2029\202F\205F\3000\FEFF';
begin
  if v_actor is null then
    raise exception 'set_restaurant_storefront_home_content: authentication required' using errcode='42501';
  end if;
  if p_client_request_id is null or p_organization_id is null or p_restaurant_id is null
    or p_expected_version is null or p_expected_version < 0 then
    raise exception 'set_restaurant_storefront_home_content: invalid required input' using errcode='42501';
  end if;
  -- Authority is freshly resolved before any ledger replay or profile disclosure.
  v_rank := app.actor_rank_in_scope(p_organization_id,p_restaurant_id,null);
  if v_rank = 0 then
    raise exception 'set_restaurant_storefront_home_content: no covering membership' using errcode='42501';
  end if;
  if v_rank < 2 then
    perform app.management_audit(p_organization_id,p_restaurant_id,null,
      'settings.storefront.update_denied',null,
      jsonb_build_object('restaurant_id',p_restaurant_id,'setting','storefront_profile'));
    return jsonb_build_object('ok',false,'error','permission_denied','entity',c_entity);
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    return jsonb_build_object('ok',false,'error','invalid','reason','patch_not_object','entity',c_entity);
  end if;
  for v_key in select jsonb_object_keys(p_patch) loop
    if not (v_key = any(c_fields)) then
      return jsonb_build_object('ok',false,'error','invalid','reason','unknown_field','field',v_key,'entity',c_entity);
    end if;
  end loop;
  foreach v_key in array c_fields loop
    if not (p_patch ? v_key) then
      return jsonb_build_object('ok',false,'error','invalid','reason','missing_field','field',v_key,'entity',c_entity);
    end if;
  end loop;

  -- Same lock order as the generic profile/media writers. Never create a profile.
  perform 1 from public.restaurants r where r.id=p_restaurant_id
    and r.organization_id=p_organization_id and r.deleted_at is null for update;
  if not found then
    return jsonb_build_object('ok',false,'error','not_found','entity',c_entity);
  end if;
  select * into v_profile from public.restaurant_storefront_profiles p
    where p.restaurant_id=p_restaurant_id and p.organization_id=p_organization_id
      and p.deleted_at is null for update;
  if not found then
    return jsonb_build_object('ok',false,'error','not_found','entity',c_entity);
  end if;
  -- A waiter must not reuse an authority verdict taken before another writer
  -- held these locks: membership may have been revoked while this call waited.
  if app.actor_rank_in_scope(p_organization_id,p_restaurant_id,null) < 2 then
    raise exception 'set_restaurant_storefront_home_content: authority changed' using errcode='42501';
  end if;
  -- RAW patch identity: even normalization-equivalent changes are not a replay.
  v_fingerprint := md5(jsonb_build_object('org',p_organization_id,'restaurant',p_restaurant_id,
    'expected_version',p_expected_version,'patch',p_patch)::text);
  v_replay := app.management_idem_check(v_actor,p_client_request_id,c_operation,v_fingerprint);
  if v_replay is not null then return v_replay; end if;
  if v_profile.version <> p_expected_version then
    return jsonb_build_object('ok',false,'error','version_conflict','entity',c_entity,
      'restaurant_id',p_restaurant_id,'version',v_profile.version,
      'slug',v_profile.slug,'is_published',v_profile.is_published);
  end if;
  foreach v_key in array c_fields loop
    v_value := p_patch -> v_key;
    if jsonb_typeof(v_value) not in ('string','null') then
      return jsonb_build_object('ok',false,'error','invalid','reason',v_key||'_invalid','field',v_key,'entity',c_entity);
    end if;
    v_text := v_value #>> '{}';
    if v_text ~ '[\x01-\x1f\x7f]' then
      return jsonb_build_object('ok',false,'error','invalid','reason',v_key||'_invalid','field',v_key,'entity',c_entity);
    end if;
    v_text := nullif(btrim(v_text,c_trim),'');
    v_limit := case v_key when 'hero_headline' then 120 when 'hero_subline' then 180 else 240 end;
    if char_length(v_text) > v_limit then
      return jsonb_build_object('ok',false,'error','invalid','reason',v_key||'_invalid','field',v_key,'entity',c_entity);
    end if;
    v_normalized := v_normalized || jsonb_build_object(v_key,v_text);
  end loop;
  v_result := jsonb_build_object('ok',true,'idempotent_replay',false,'entity',c_entity,
    'restaurant_id',p_restaurant_id,'version',v_profile.version+1,
    'slug',v_profile.slug,'is_published',v_profile.is_published);
  v_replay := app.management_claim_request(v_actor,p_client_request_id,c_operation,v_fingerprint,v_result);
  if v_replay is not null then return v_replay; end if;
  v_old := to_jsonb(v_profile);
  update public.restaurant_storefront_profiles set
    hero_headline=v_normalized->>'hero_headline',hero_subline=v_normalized->>'hero_subline',
    announcement_text=v_normalized->>'announcement_text',version=v_profile.version+1
    where restaurant_id=p_restaurant_id and organization_id=p_organization_id;
  select to_jsonb(p) into v_new from public.restaurant_storefront_profiles p where p.restaurant_id=p_restaurant_id;
  perform app.management_audit(p_organization_id,p_restaurant_id,null,'settings.storefront.updated',v_old,v_new);
  return v_result;
end; $$;

create function public.set_restaurant_storefront_home_content(
  p_client_request_id uuid,p_organization_id uuid,p_restaurant_id uuid,
  p_expected_version integer,p_patch jsonb)
returns jsonb language sql volatile security invoker set search_path='' as $$
  select app.set_restaurant_storefront_home_content(p_client_request_id,p_organization_id,
    p_restaurant_id,p_expected_version,p_patch);
$$;
revoke all on function app.set_restaurant_storefront_home_content(uuid,uuid,uuid,integer,jsonb),
  public.set_restaurant_storefront_home_content(uuid,uuid,uuid,integer,jsonb)
  from public,anon,authenticated,service_role;
grant execute on function app.set_restaurant_storefront_home_content(uuid,uuid,uuid,integer,jsonb),
  public.set_restaurant_storefront_home_content(uuid,uuid,uuid,integer,jsonb) to authenticated;

-- One existing menu invocation and one shared statement snapshot. No duplicate
-- menu/price/availability implementation; no change to the original RPC/ACLs.
create function public.storefront_menu_v2(p_slug text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_menu jsonb;
  v_content jsonb;
begin
  v_menu := public.storefront_menu(p_slug);
  if v_menu->>'ok' is distinct from 'true' then return v_menu; end if;
  if v_menu#>>'{restaurant,slug}' is distinct from p_slug then
    return jsonb_build_object('ok',false,'error','not_found','entity','storefront_menu');
  end if;
  select jsonb_build_object('hero_headline',p.hero_headline,'hero_subline',p.hero_subline,
    'announcement_text',p.announcement_text) into v_content
  from public.restaurant_storefront_profiles p
    join public.organizations o on o.id=p.organization_id
    join public.restaurants r on r.organization_id=p.organization_id and r.id=p.restaurant_id
    join public.branches b on b.organization_id=p.organization_id and b.restaurant_id=p.restaurant_id
      and b.id=p.storefront_branch_id
  where p.slug=v_menu#>>'{restaurant,slug}' and p.deleted_at is null and p.is_published
    and o.status='active' and o.deleted_at is null
    and r.status='active' and r.deleted_at is null
    and b.status='active' and b.deleted_at is null
    and coalesce(b.timezone,r.timezone) is not null
    and coalesce(r.currency_override,o.default_currency)='ILS'
    and (not b.tax_enabled or b.tax_mode='exclusive');
  if not found then
    return jsonb_build_object('ok',false,'error','not_found','entity','storefront_menu');
  end if;
  return v_menu || jsonb_build_object('home_content',v_content);
end; $$;
revoke all on function public.storefront_menu_v2(text) from public,anon,authenticated,service_role;
grant execute on function public.storefront_menu_v2(text) to anon,service_role;

comment on function public.storefront_menu_v2(text) is
  'BIZBOT-STOREFRONT-HOME-CONTENT-001: single-snapshot versioned public menu; existing menu called exactly once, plus bounded public Home copy from the same published tenant/restaurant/branch. No order or employee authority.';
comment on function app.set_restaurant_storefront_home_content(uuid,uuid,uuid,integer,jsonb) is
  'BIZBOT-STOREFRONT-HOME-CONTENT-001: existing-profile-only manager CAS write. Complete raw three-key object binds request identity; authority checked before replay. No generic-writer, onboarding, pricing, ordering or printing changes.';
commit;
