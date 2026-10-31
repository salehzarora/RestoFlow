-- BIZBOT-STOREFRONT-SEO-DISCOVERY-001: additive, read-only backend surface.
-- No indexing activation, merchant consent seed, legacy replacement or worker.
begin;

create table app.storefront_seo_release_gate_v1 (
  singleton boolean primary key default true check (singleton),
  policy_version integer not null default 1 check (policy_version > 0),
  enabled boolean not null default false,
  revision bigint not null default 1 check (revision > 0)
);
alter table app.storefront_seo_release_gate_v1 enable row level security;
alter table app.storefront_seo_release_gate_v1 force row level security;
revoke all on app.storefront_seo_release_gate_v1 from public, anon, authenticated, service_role;
revoke all (singleton, policy_version, enabled, revision) on app.storefront_seo_release_gate_v1 from public, anon, authenticated, service_role;
insert into app.storefront_seo_release_gate_v1(singleton, policy_version, enabled, revision) values (true, 1, false, 1);
comment on table app.storefront_seo_release_gate_v1 is
  'Private versioned platform release gate, default OFF. No public setter or merchant control. Missing/unsupported state is UNKNOWN, never ON. No restaurant consent seed.';

-- All accepted slugs are ASCII: UTF8 encoding is deterministic for that domain.
-- The predicate is also enforced here so invalid text cannot enter the index.
create function app.storefront_seo_partition_v1(p_slug text)
returns integer language sql immutable strict parallel safe set search_path = '' as $$
  select case when p_slug ~ '^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$'
    then get_byte(sha256(convert_to(p_slug, 'UTF8')), 0) % 16 else null end;
$$;
revoke all on function app.storefront_seo_partition_v1(text) from public, anon, authenticated, service_role;

create index storefront_seo_discovery_slug_v1 on public.restaurant_storefront_profiles(slug collate "C")
  where is_published and deleted_at is null;
create index storefront_seo_discovery_partition_v1 on public.restaurant_storefront_profiles(
  app.storefront_seo_partition_v1(slug), slug collate "C") where is_published and deleted_at is null;
create index storefront_seo_discovery_consent_v1 on app.restaurant_storefront_seo_consent_v1(organization_id, restaurant_id)
  where consent_enabled;

-- Internal envelope: {ok,menu,eligible} or {ok:false,error}. No private IDs or
-- reasons are returned even here. Public wrappers project only their contracts.
-- STABLE is essential: nested STABLE readers share the invoking statement's
-- snapshot. Do not change this chain to VOLATILE or cache positive eligibility.
create function app.storefront_seo_read_v1(p_slug text, p_bounded boolean default false)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  scope_row record;
  menu_result jsonb;
  gate_row record;
  gate_known boolean := false;
  consent_value boolean;
  eligibility boolean;
  row_count integer;
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    return jsonb_build_object('ok', false, 'error', 'unavailable');
  end if;
  if p_slug is null or p_slug !~ '^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$' then
    return jsonb_build_object('ok', false, 'error', 'not_found');
  end if;
  -- This is publication verification, not an SEO dependency. Its failure must
  -- never authorize an old published menu as a freshly checked response.
  select p.organization_id, p.restaurant_id, p.storefront_branch_id into scope_row
    from public.restaurant_storefront_profiles p
    join public.organizations o on o.id = p.organization_id
    join public.restaurants r on (r.organization_id, r.id) = (p.organization_id, p.restaurant_id)
    join public.branches b on (b.organization_id, b.restaurant_id, b.id) = (p.organization_id, p.restaurant_id, p.storefront_branch_id)
   where p.slug = p_slug and p.deleted_at is null and p.is_published
     and o.status = 'active' and o.deleted_at is null
     and r.status = 'active' and r.deleted_at is null
     and b.status = 'active' and b.deleted_at is null;
  if not found then return jsonb_build_object('ok', false, 'error', 'not_found'); end if;

  if p_bounded then
    -- Bounded pre-counts use the base reader's live, ancestry and branch
    -- predicates. They precede JSON aggregation; v4 remains the final authority.
    select count(*) into row_count from (
      select 1 from public.menu_categories c
       where c.organization_id = scope_row.organization_id and c.restaurant_id = scope_row.restaurant_id
         and c.is_active and c.deleted_at is null and (c.branch_id is null or c.branch_id = scope_row.storefront_branch_id)
       limit 101
    ) bounded;
    if row_count > 100 then return jsonb_build_object('ok', false, 'error', 'payload_limit'); end if;
    select count(*) into row_count from (
      select 1 from public.menu_items i join public.menu_categories c
        on c.organization_id = i.organization_id and c.restaurant_id = scope_row.restaurant_id and c.id = i.menu_category_id
       where i.organization_id = scope_row.organization_id and i.restaurant_id = scope_row.restaurant_id
         and i.is_active and i.deleted_at is null and (i.branch_id is null or i.branch_id = scope_row.storefront_branch_id)
         and c.is_active and c.deleted_at is null and (c.branch_id is null or c.branch_id = scope_row.storefront_branch_id)
       limit 501
    ) bounded;
    if row_count > 500 then return jsonb_build_object('ok', false, 'error', 'payload_limit'); end if;
    select count(*) into row_count from (
      select 1 from public.modifiers m
      join public.menu_items i on i.organization_id = m.organization_id and i.restaurant_id = scope_row.restaurant_id and i.id = m.menu_item_id
      join public.menu_categories c on c.organization_id = i.organization_id and c.restaurant_id = scope_row.restaurant_id and c.id = i.menu_category_id
       where m.organization_id = scope_row.organization_id and m.restaurant_id = scope_row.restaurant_id
         and m.is_active and m.deleted_at is null and (m.branch_id is null or m.branch_id = scope_row.storefront_branch_id)
         and i.is_active and i.deleted_at is null and (i.branch_id is null or i.branch_id = scope_row.storefront_branch_id)
         and c.is_active and c.deleted_at is null and (c.branch_id is null or c.branch_id = scope_row.storefront_branch_id)
       limit 2001
    ) bounded;
    if row_count > 2000 then return jsonb_build_object('ok', false, 'error', 'payload_limit'); end if;
    select count(*) into row_count from (
      select 1 from public.modifier_options mo
      join public.modifiers m on m.organization_id = mo.organization_id and m.id = mo.modifier_id
      join public.menu_items i on i.organization_id = m.organization_id and i.restaurant_id = scope_row.restaurant_id and i.id = m.menu_item_id
      join public.menu_categories c on c.organization_id = i.organization_id and c.restaurant_id = scope_row.restaurant_id and c.id = i.menu_category_id
       where mo.organization_id = scope_row.organization_id and mo.restaurant_id = scope_row.restaurant_id
         and mo.is_active and mo.deleted_at is null and mo.price_delta_minor >= 0
         and (mo.branch_id is null or mo.branch_id = scope_row.storefront_branch_id)
         and m.is_active and m.deleted_at is null and (m.branch_id is null or m.branch_id = scope_row.storefront_branch_id)
         and i.is_active and i.deleted_at is null and (i.branch_id is null or i.branch_id = scope_row.storefront_branch_id)
         and c.is_active and c.deleted_at is null and (c.branch_id is null or c.branch_id = scope_row.storefront_branch_id)
       limit 8001
    ) bounded;
    if row_count > 8000 then return jsonb_build_object('ok', false, 'error', 'payload_limit'); end if;
  end if;

  menu_result := public.storefront_menu_v4(p_slug);
  if menu_result ->> 'ok' is distinct from 'true' then
    return jsonb_build_object('ok', false, 'error', case
      when menu_result ->> 'error' in ('not_found', 'payload_limit') then menu_result ->> 'error' else 'unavailable' end);
  end if;
  if menu_result #>> '{restaurant,slug}' is distinct from p_slug then
    return jsonb_build_object('ok', false, 'error', 'unavailable');
  end if;

  -- Isolate SEO-only errors from ordinary menu availability. Unknown is NULL,
  -- never an affirmative grant and never a fabricated consent=false statement.
  begin
    select g.* into gate_row from app.storefront_seo_release_gate_v1 g where g.singleton;
    gate_known := found;
    if gate_known and gate_row.policy_version = 1 and gate_row.revision > 0 and gate_row.enabled is not null then
      if not gate_row.enabled then eligibility := false;
      else
        select coalesce((select c.consent_enabled from app.restaurant_storefront_seo_consent_v1 c
          where (c.organization_id, c.restaurant_id) = (scope_row.organization_id, scope_row.restaurant_id)), false) into consent_value;
        eligibility := consent_value;
      end if;
    end if;
  exception when query_canceled or others then
    eligibility := null;
  end;
  return jsonb_build_object('ok', true, 'menu', menu_result, 'eligible', eligibility);
exception when query_canceled or others then
  return jsonb_build_object('ok', false, 'error', 'unavailable');
end;
$$;
revoke all on function app.storefront_seo_read_v1(text, boolean) from public, anon, authenticated, service_role;

create function public.storefront_seo_page_v1(p_slug text)
returns jsonb language plpgsql stable security definer set search_path = ''
set statement_timeout = '2s' set lock_timeout = '500ms' set default_transaction_isolation = 'read committed' set timezone = 'UTC' as $$
declare result jsonb; evaluated timestamptz := statement_timestamp();
begin
  result := app.storefront_seo_read_v1(p_slug, false);
  if result ->> 'ok' is distinct from 'true' then
    return jsonb_build_object('ok', false, 'schema', 1, 'error', result ->> 'error');
  end if;
  return jsonb_build_object('ok', true, 'schema', 1, 'menu', result -> 'menu', 'seo',
    jsonb_build_object('eligible', result -> 'eligible', 'evaluated_at', evaluated, 'valid_until', evaluated + interval '10 seconds'));
exception when query_canceled or others then
  return jsonb_build_object('ok', false, 'schema', 1, 'error', 'unavailable');
end;
$$;
revoke all on function public.storefront_seo_page_v1(text) from public, anon, authenticated, service_role;
grant execute on function public.storefront_seo_page_v1(text) to anon;

create function public.storefront_seo_discovery_v1(p_after_slug text default null, p_limit integer default 10, p_partition integer default null)
returns jsonb language plpgsql stable security definer set search_path = ''
set statement_timeout = '2s' set lock_timeout = '500ms' set default_transaction_isolation = 'read committed' set timezone = 'UTC' as $$
declare
  gate_row record;
  candidate record;
  result jsonb;
  response jsonb;
  items jsonb := '[]'::jsonb;
  scanned integer := 0;
  last_returned text;
  more boolean := false;
  evaluated timestamptz := statement_timestamp();
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    return jsonb_build_object('ok', false, 'schema', 1, 'error', 'unavailable');
  end if;
  if p_limit is null or p_limit < 1 or p_limit > 25
     or (p_after_slug is not null and p_after_slug !~ '^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$')
     or (p_partition is not null and (p_partition < 0 or p_partition > 15)) then
    return jsonb_build_object('ok', false, 'schema', 1, 'error', 'invalid_request');
  end if;
  select g.* into gate_row from app.storefront_seo_release_gate_v1 g where g.singleton;
  if not found or gate_row.policy_version is distinct from 1 or gate_row.revision is null
     or gate_row.revision <= 0 or gate_row.enabled is null then
    return jsonb_build_object('ok', false, 'schema', 1, 'error', 'unavailable');
  end if;
  if gate_row.enabled then
    -- Two query branches let the matching C-order or partition index serve the
    -- keyset. Selection is at most 65; candidate 65 is never evaluated/exposed.
    for candidate in
      select picked.slug from (
        (select p.slug from public.restaurant_storefront_profiles p
          join app.restaurant_storefront_seo_consent_v1 c on (c.organization_id, c.restaurant_id) = (p.organization_id, p.restaurant_id) and c.consent_enabled
          join public.organizations o on o.id = p.organization_id and o.status = 'active' and o.deleted_at is null
          join public.restaurants r on (r.organization_id, r.id) = (p.organization_id, p.restaurant_id) and r.status = 'active' and r.deleted_at is null
          join public.branches b on (b.organization_id, b.restaurant_id, b.id) = (p.organization_id, p.restaurant_id, p.storefront_branch_id) and b.status = 'active' and b.deleted_at is null
         where p_partition is null and p.is_published and p.deleted_at is null
           and (p_after_slug is null or p.slug collate "C" > p_after_slug collate "C")
         order by p.slug collate "C" limit 65)
        union all
        (select p.slug from public.restaurant_storefront_profiles p
          join app.restaurant_storefront_seo_consent_v1 c on (c.organization_id, c.restaurant_id) = (p.organization_id, p.restaurant_id) and c.consent_enabled
          join public.organizations o on o.id = p.organization_id and o.status = 'active' and o.deleted_at is null
          join public.restaurants r on (r.organization_id, r.id) = (p.organization_id, p.restaurant_id) and r.status = 'active' and r.deleted_at is null
          join public.branches b on (b.organization_id, b.restaurant_id, b.id) = (p.organization_id, p.restaurant_id, p.storefront_branch_id) and b.status = 'active' and b.deleted_at is null
         where p_partition is not null and app.storefront_seo_partition_v1(p.slug) = p_partition
           and p.is_published and p.deleted_at is null
           and (p_after_slug is null or p.slug collate "C" > p_after_slug collate "C")
         order by p.slug collate "C" limit 65)
      ) picked order by picked.slug collate "C"
    loop
      scanned := scanned + 1;
      if scanned > 64 then
        return jsonb_build_object('ok', false, 'schema', 1, 'error', 'budget_unavailable');
      end if;
      result := app.storefront_seo_read_v1(candidate.slug, true);
      if result ->> 'ok' is distinct from 'true' then
        if result ->> 'error' in ('not_found', 'payload_limit') then continue; end if;
        return jsonb_build_object('ok', false, 'schema', 1, 'error', 'unavailable');
      end if;
      if result -> 'eligible' = 'null'::jsonb or result -> 'eligible' is null then
        return jsonb_build_object('ok', false, 'schema', 1, 'error', 'unavailable');
      end if;
      if result -> 'eligible' = 'true'::jsonb then
        if jsonb_array_length(items) = p_limit then more := true; exit; end if;
        items := items || jsonb_build_array(jsonb_build_object('path', '/s/' || candidate.slug || '/menu'));
        last_returned := candidate.slug;
      end if;
    end loop;
  end if;
  response := jsonb_build_object('ok', true, 'schema', 1, 'items', items,
    'next_after_slug', case when more then last_returned else null end, 'has_more', more,
    'evaluated_at', evaluated, 'valid_until', evaluated + interval '10 seconds');
  if octet_length(convert_to(response::text, 'UTF8')) > 16384 then
    return jsonb_build_object('ok', false, 'schema', 1, 'error', 'budget_unavailable');
  end if;
  return response;
exception when query_canceled or others then
  return jsonb_build_object('ok', false, 'schema', 1, 'error', 'unavailable');
end;
$$;
revoke all on function public.storefront_seo_discovery_v1(text, integer, integer) from public, anon, authenticated, service_role;
grant execute on function public.storefront_seo_discovery_v1(text, integer, integer) to anon;

comment on function public.storefront_seo_page_v1(text) is
  'Versioned public menu+SEO read, no indexing release. Exact v4 menu and eligibility share a READ COMMITTED statement snapshot; nullable eligibility never grants indexing. No persistent cache or mutation.';
comment on function public.storefront_seo_discovery_v1(text, integer, integer) is
  'Current consent+gate+live-v4 canonical paths only. Limit 1..25, candidate evaluation <=64, result <=16KiB. No partial results on budget/outage. Deadline must be enforced before statement invocation.';
notify pgrst, 'reload schema';
commit;
