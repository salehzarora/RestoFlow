-- BIZBOT-STOREFRONT-BRAND-HERO-UX-003. Local candidate; no hosted application.
-- Detail photos reuse explicitly published Original registrations and c4 w960.
-- Never expose a private key, change a selection, or reinterpret v5-v9.
set local lock_timeout = '5s';
set local statement_timeout = '60s';

create function app.storefront_product_original_images_v1(
  p_org uuid, p_restaurant uuid, p_branch uuid, p_item_ids uuid[]
) returns jsonb language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'item_id', available.item_id,
    'url', '/storage/v1/object/public/storefront-media/' || available.object_key,
    'width', available.width, 'height', available.height
  ) order by available.item_id), '[]'::jsonb)
  from (
    select distinct on (i.id) i.id as item_id, m.object_key, m.width, m.height
    from public.menu_items i
    join public.menu_categories c on c.id = i.menu_category_id
      and c.organization_id = i.organization_id and c.restaurant_id = i.restaurant_id
    join app.storefront_product_derivatives d on d.item_id = i.id
      and d.organization_id = i.organization_id and d.restaurant_id = i.restaurant_id
      and d.treatment = 'original' and d.candidate_key = d.original_key
    join public.storefront_media m on m.product_derivative_id = d.id
      and m.organization_id = d.organization_id and m.restaurant_id = d.restaurant_id
    where i.organization_id = p_org and i.restaurant_id = p_restaurant
      and i.id = any(p_item_ids)
      and i.is_active and i.deleted_at is null and (i.branch_id is null or i.branch_id = p_branch)
      and c.is_active and c.deleted_at is null and (c.branch_id is null or c.branch_id = p_branch)
      and app.storefront_product_current_v1(d.id, p_org, p_restaurant)
      and m.source_bucket = 'menu-images' and m.source_key = d.original_key
      and m.item_source_snapshot is null and m.variant = 'w960'
      and m.published_at is not null and m.unpublished_at is null
      and m.width between 1 and 960 and m.height between 1 and 960
      and m.bytes between 1 and 524288
      and m.content_hash ~ '^[0-9a-f]{64}$'
      and m.object_key = app.storefront_media_prefix(p_restaurant) || '/' || m.content_hash || '.webp'
      and exists (
        select 1 from storage.objects o
        where o.bucket_id = 'storefront-media' and o.name = m.object_key
          and o.metadata->>'mimetype' = 'image/webp' and o.metadata->>'size' = m.bytes::text
      )
    order by i.id, m.published_at desc, d.created_at desc, d.id desc
  ) available;
$$;

create function public.storefront_menu_v10(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  menu jsonb;
  profile public.restaurant_storefront_profiles%rowtype;
  served_ids uuid[];
begin
  menu := public.storefront_menu_v9(p_slug);
  if menu->>'ok' is distinct from 'true' or menu#>>'{restaurant,slug}' is distinct from p_slug then
    return menu;
  end if;
  select * into profile from public.restaurant_storefront_profiles
    where slug = p_slug and is_published and deleted_at is null;
  -- The already admitted, bounded catalogue alone determines eligible identities.
  select coalesce(array_agg((item->>'id')::uuid), '{}'::uuid[]) into served_ids
    from jsonb_array_elements(menu->'items') item;
  return menu || jsonb_build_object('product_original_images_v1',
    app.storefront_product_original_images_v1(profile.organization_id, profile.restaurant_id,
      profile.storefront_branch_id, served_ids));
end;
$$;

revoke all on function app.storefront_product_original_images_v1(uuid,uuid,uuid,uuid[]),
  public.storefront_menu_v10(text) from public, anon, authenticated, service_role;
grant execute on function public.storefront_menu_v10(text) to anon, authenticated;
comment on function public.storefront_menu_v10(text) is
  'BIZBOT-STOREFRONT-BRAND-HERO-UX-003: optional bounded current published Original detail photo; selected product and older public contracts unchanged.';
