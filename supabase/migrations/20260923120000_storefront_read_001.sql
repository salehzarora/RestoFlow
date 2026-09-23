-- ============================================================================
-- STOREFRONT-READ-001 — the first REAL storefront read: published restaurant
-- profile + menu, served to the anonymous Postgres role through ONE
-- enumerated, anon-only SECURITY DEFINER function in schema public.
--
-- Sealed plan: worktrees/output/storefront-read-001-plan-20260923T152536Z/
-- (STOREFRONT_READ_001_EXECUTION_PACKET.md §4.3–§4.4, §5). Owner decisions
-- taken with the implementation authorization (2026-09-23): D0 (the read-slice
-- security content of §5 is executed HERE under independent review), D1
-- (ratify DECISION D-037 as written — anon-only grants — with ONE narrow
-- amendment: only the explicitly enumerated Storefront public functions may be
-- SECURITY DEFINER; no general exception), D2/D13 (server-rendered read path).
--
-- WHAT THIS FILE ADDS
--   1. app.storefront_opening_hours_is_valid(jsonb)   — CHECK helper (IMMUTABLE)
--   2. app.storefront_service_window(jsonb, text, ts)  — today's window / open_now
--   3. app.storefront_media_prefix(uuid)               — opaque per-restaurant prefix
--   4. public.storefront_media                         — PUBLISHED derivative map
--   5. public.restaurant_storefront_profiles           — slug / profile / hours /
--                                                        publish state (1:1 restaurants)
--   6. storage bucket `storefront-media` (PUBLIC, 512 KiB, image/webp) + policies
--      gated by app.can_write_storefront_media (rank >= manager over the restaurant)
--   7. app.set_restaurant_storefront_profile (CAS write, audited) + public wrapper
--      app.get_restaurant_storefront_profile (manager+ read)      + public wrapper
--   8. public.storefront_menu(p_slug text) — THE anon-only read contract
--
-- SECURITY POSTURE (D-011 / D-012 / D-037 as amended / T-016 / T-017)
--   * `anon` gains EXECUTE on EXACTLY ONE public function: storefront_menu(text).
--     The grant set is explicit because the hosted `postgres` default ACL in
--     `public` still stamps `authenticated=X, service_role=X` on every new
--     function (SEC-001 removed only `anon`): revoke PUBLIC, revoke anon, revoke
--     authenticated, grant anon. `service_role` keeps the stamped EXECUTE like
--     every other public function (stated, not hidden).
--   * The function resolves scope from the SLUG ONLY, calls no membership
--     helper (current_app_user_id / current_org_id / has_scope /
--     has_role_in_scope / set_config / auth.uid — asserted on prosrc by
--     storefront_read_001_test.sql) and reads the catalog tables directly as
--     its owner. `anon` still has NO privilege on any table and NO USAGE on
--     schema `app` (T-016 B1/C1 unchanged).
--   * Uniform `not_found` for invalid / unknown / unpublished / suspended /
--     deleted / NULL-timezone / non-ILS / inclusive-tax — never distinguishes
--     "unknown" from "unpublished" (anti-oracle).
--   * Never served: sku, prep_minutes, kitchen_note, attributes,
--     default_station_id, item_type, sizes/variants, kitchen_meat,
--     allow_quantity/max_quantity, image_path keys, any org/restaurant/branch/
--     device UUID, membership or staff data. Exact served-key set asserted.
--   * Execution bound: a function-level SET statement_timeout cannot bound the
--     statement already executing, so the bound is the ROLE-level `anon`
--     timeout read on hosted (pg_roles.rolconfig) in the pre-apply drift watch.
--   * SEC-001 (20260913164029) is NOT re-runnable once this file exists: its
--     schema-wide `revoke ... from anon` would strip this grant and its step-6
--     assertion (anon_exec = 0) would abort. Recorded in DEPLOYMENT.md §16.
--
-- Money: integer minor units only (base_price_minor / price_delta_minor bigint,
-- tax as basis points) — D-007. No float anywhere in this file.
--
-- NOT applied to hosted by this file. Hosted apply is a separately authorised
-- step after independent review and the DEPLOYMENT.md §16 drift watch.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Opening-hours validator (IMMUTABLE; used by the CHECK and by the writer).
--    Shape: {"weekly":[{"dow":0..6,"open":"HH:MM","close":"HH:MM"}, ...],
--            "exceptions":[{"date":"YYYY-MM-DD","closed":true} |
--                          {"date":"YYYY-MM-DD","open":"HH:MM","close":"HH:MM"}]}
--    A window whose close is EARLIER than its open crosses midnight (e.g.
--    18:00 -> 02:00); open = close is refused (no zero-length / 24 h form).
--    Windows of one day must not overlap; if they do, the earliest-start window
--    is the one reported by app.storefront_service_window.
-- ----------------------------------------------------------------------------
create or replace function app.storefront_opening_hours_is_valid(p_hours jsonb)
  returns boolean
  language plpgsql
  immutable
  set search_path = ''
as $$
declare
  v_w    jsonb;
  v_e    jsonb;
  v_keys text[];
  c_hhmm constant text := '^([01][0-9]|2[0-3]):[0-5][0-9]$';
begin
  if p_hours is null or jsonb_typeof(p_hours) <> 'object' then return false; end if;
  select coalesce(array_agg(k), '{}') into v_keys from jsonb_object_keys(p_hours) k;
  if exists (select 1 from unnest(v_keys) k where k not in ('weekly', 'exceptions')) then return false; end if;
  if p_hours ? 'weekly' then
    if jsonb_typeof(p_hours -> 'weekly') <> 'array' then return false; end if;
    if jsonb_array_length(p_hours -> 'weekly') > 21 then return false; end if;
    for v_w in select * from jsonb_array_elements(p_hours -> 'weekly') loop
      if jsonb_typeof(v_w) <> 'object' then return false; end if;
      if exists (select 1 from jsonb_object_keys(v_w) k where k not in ('dow', 'open', 'close')) then return false; end if;
      if jsonb_typeof(v_w -> 'dow') <> 'number' or (v_w ->> 'dow') !~ '^[0-6]$' then return false; end if;
      if jsonb_typeof(v_w -> 'open') <> 'string' or (v_w ->> 'open') !~ c_hhmm then return false; end if;
      if jsonb_typeof(v_w -> 'close') <> 'string' or (v_w ->> 'close') !~ c_hhmm then return false; end if;
      if (v_w ->> 'open') = (v_w ->> 'close') then return false; end if;
    end loop;
  end if;
  if p_hours ? 'exceptions' then
    if jsonb_typeof(p_hours -> 'exceptions') <> 'array' then return false; end if;
    if jsonb_array_length(p_hours -> 'exceptions') > 62 then return false; end if;
    for v_e in select * from jsonb_array_elements(p_hours -> 'exceptions') loop
      if jsonb_typeof(v_e) <> 'object' then return false; end if;
      if exists (select 1 from jsonb_object_keys(v_e) k where k not in ('date', 'closed', 'open', 'close')) then return false; end if;
      if jsonb_typeof(v_e -> 'date') <> 'string' or (v_e ->> 'date') !~ '^[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$' then return false; end if;
      if coalesce(jsonb_typeof(v_e -> 'closed'), 'null') = 'boolean' and (v_e ->> 'closed')::boolean then
        if v_e ? 'open' or v_e ? 'close' then return false; end if;
      else
        if v_e ? 'closed' then return false; end if;                 -- closed:false is not a shape
        if jsonb_typeof(v_e -> 'open') <> 'string' or (v_e ->> 'open') !~ c_hhmm then return false; end if;
        if jsonb_typeof(v_e -> 'close') <> 'string' or (v_e ->> 'close') !~ c_hhmm then return false; end if;
        if (v_e ->> 'open') = (v_e ->> 'close') then return false; end if;
      end if;
    end loop;
  end if;
  return true;
end;
$$;

comment on function app.storefront_opening_hours_is_valid(jsonb) is
  'STOREFRONT-READ-001: shape validator for restaurant_storefront_profiles.opening_hours ({weekly:[{dow,open,close}], exceptions:[{date,closed}|{date,open,close}]}, HH:MM, <= 21 weekly windows, <= 62 exceptions). IMMUTABLE so it can back the CHECK constraint.';

-- ----------------------------------------------------------------------------
-- 2. Today's service window in the branch timezone. Returns the CURRENT window
--    when open (open_now = true, opens/closes as HH:MM), else the next window
--    that starts TODAY (local date) as opens/closes — null when no window
--    starts today — and, in either closed case, next_open = the next opening
--    instant within 7 days (the only forward pointer across days). Windows
--    crossing midnight are handled by scanning yesterday..+7 days. STABLE:
--    named time zones resolve through the session's tz database.
-- ----------------------------------------------------------------------------
create or replace function app.storefront_service_window(p_hours jsonb, p_tz text, p_at timestamptz)
  returns table (opens text, closes text, open_now boolean, next_open timestamptz)
  language plpgsql
  stable
  set search_path = ''
as $$
declare
  v_local      timestamp := (p_at at time zone p_tz);
  v_day        date;
  v_off        integer;
  v_windows    jsonb;
  v_ex         jsonb;
  v_w          jsonb;
  v_open       time;
  v_close      time;
  v_start      timestamp;
  v_end        timestamp;
  v_cur_start  timestamp;
  v_cur_end    timestamp;
  v_next_start timestamp;
  v_next_end   timestamp;
begin
  opens := null; closes := null; open_now := false; next_open := null;
  for v_off in -1..7 loop
    v_day := (v_local::date) + v_off;
    select e into v_ex
      from jsonb_array_elements(coalesce(p_hours -> 'exceptions', '[]'::jsonb)) e
     where (e ->> 'date') = to_char(v_day, 'YYYY-MM-DD')
     limit 1;
    if v_ex is not null then
      if coalesce(jsonb_typeof(v_ex -> 'closed'), 'null') = 'boolean' and (v_ex ->> 'closed')::boolean then
        continue;
      end if;
      v_windows := jsonb_build_array(jsonb_build_object('open', v_ex ->> 'open', 'close', v_ex ->> 'close'));
    else
      select coalesce(jsonb_agg(w), '[]'::jsonb) into v_windows
        from jsonb_array_elements(coalesce(p_hours -> 'weekly', '[]'::jsonb)) w
       where (w ->> 'dow')::integer = extract(dow from v_day)::integer;
    end if;
    for v_w in select * from jsonb_array_elements(v_windows) loop
      v_open  := (v_w ->> 'open')::time;
      v_close := (v_w ->> 'close')::time;
      v_start := v_day + v_open;
      v_end   := case when v_close > v_open then v_day + v_close else (v_day + 1) + v_close end;
      if v_local >= v_start and v_local < v_end then
        if v_cur_start is null or v_start < v_cur_start then
          v_cur_start := v_start; v_cur_end := v_end;
        end if;
      elsif v_start > v_local then
        if v_next_start is null or v_start < v_next_start then
          v_next_start := v_start; v_next_end := v_end;
        end if;
      end if;
    end loop;
  end loop;
  if v_cur_start is not null then
    open_now := true;
    opens    := to_char(v_cur_start, 'HH24:MI');
    closes   := to_char(v_cur_end, 'HH24:MI');
    next_open := null;
  elsif v_next_start is not null then
    -- opens/closes describe TODAY only; a window on a later day is announced
    -- through next_open, never as a bare time the reader would take for today
    if v_next_start::date = v_local::date then
      opens  := to_char(v_next_start, 'HH24:MI');
      closes := to_char(v_next_end, 'HH24:MI');
    end if;
    next_open := v_next_start at time zone p_tz;
  end if;
  return next;
end;
$$;

comment on function app.storefront_service_window(jsonb, text, timestamptz) is
  'STOREFRONT-READ-001: the storefront''s current or next service window computed in the branch timezone (DST-correct; midnight-crossing windows supported). Used only inside public.storefront_menu; not granted to any app role.';

-- ----------------------------------------------------------------------------
-- 3. Opaque per-restaurant object prefix for the PUBLIC derivative bucket. A
--    published object key is `{prefix}/{sha256(bytes)}.webp`, so no tenant UUID
--    and no private object key is ever part of a public URL.
-- ----------------------------------------------------------------------------
create or replace function app.storefront_media_prefix(p_restaurant_id uuid)
  returns text
  language sql
  immutable
  set search_path = ''
as $$
  select left(encode(sha256(('storefront-media:' || p_restaurant_id::text)::bytea), 'hex'), 32);
$$;

comment on function app.storefront_media_prefix(uuid) is
  'STOREFRONT-READ-001: the opaque 32-hex prefix under which a restaurant''s published derivatives live in the public storefront-media bucket (sha256 of a salted restaurant id; not reversible to the UUID by a visitor).';

-- ----------------------------------------------------------------------------
-- 4. storefront_media — the mapping from a PRIVATE original (menu-images /
--    restaurant-logos key) to a PUBLISHED public derivative. Rows are written
--    only by the Dashboard publish action (WP-C, a separate ticket): this slice
--    creates the table, the bucket and the write gate; nothing here uploads.
-- ----------------------------------------------------------------------------
create table public.storefront_media (
  id               uuid        primary key default gen_random_uuid(),
  organization_id  uuid        not null references public.organizations (id) on delete restrict,
  restaurant_id    uuid        not null,
  source_bucket    text        not null check (source_bucket in ('menu-images', 'restaurant-logos')),
  source_key       text        not null check (length(source_key) between 1 and 512),
  variant          text        not null check (variant in ('w480', 'w960')),
  object_key       text        not null check (object_key ~ '^[0-9a-f]{32}/[0-9a-f]{64}\.webp$'),
  content_hash     text        not null check (content_hash ~ '^[0-9a-f]{64}$'),
  width            integer     not null check (width between 1 and 4096),
  height           integer     not null check (height between 1 and 4096),
  bytes            integer     not null check (bytes between 1 and 524288),
  published_at     timestamptz,
  unpublished_at   timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (organization_id, id),
  unique (object_key),
  foreign key (organization_id, restaurant_id)
    references public.restaurants (organization_id, id) on delete restrict,
  -- the object key's prefix MUST be this restaurant's opaque prefix, and the
  -- file name MUST be the content hash: an object can never be published under
  -- another restaurant's prefix or with a name that is not its own bytes.
  constraint storefront_media_key_shape check (
    split_part(object_key, '/', 1) = app.storefront_media_prefix(restaurant_id)
    and split_part(split_part(object_key, '/', 2), '.', 1) = content_hash
  ),
  constraint storefront_media_unpublish_after_publish check (
    unpublished_at is null or (published_at is not null and unpublished_at >= published_at)
  )
);

comment on table public.storefront_media is
  'STOREFRONT-READ-001: published PUBLIC derivatives (WebP, 480/960 px, <= 512 KiB) of private menu / logo originals, mapped by (source_bucket, source_key, variant). A row with published_at set and unpublished_at null is what public.storefront_menu may reference; the private original key is NEVER served. Retraction is best-effort: a copy already cached by the storage CDN or downloaded by a visitor cannot be recalled. Writes: Dashboard publish action (later ticket) — no anon path, no service-role path.';

-- one live derivative per (source, variant); re-publishing writes a new hash
create unique index storefront_media_live_source_idx
  on public.storefront_media (organization_id, restaurant_id, source_bucket, source_key, variant)
  where unpublished_at is null;
create index storefront_media_restaurant_idx
  on public.storefront_media (organization_id, restaurant_id);

create trigger storefront_media_set_updated_at
  before update on public.storefront_media
  for each row execute function app.set_updated_at();

alter table public.storefront_media enable row level security;
alter table public.storefront_media force  row level security;
-- RPC-only surface (D-011): explicit deny policies + no app-role grants.
create policy storefront_media_sel_deny on public.storefront_media for select to authenticated using (false);
create policy storefront_media_ins_deny on public.storefront_media for insert to authenticated with check (false);
create policy storefront_media_upd_deny on public.storefront_media for update to authenticated using (false) with check (false);
create policy storefront_media_del_deny on public.storefront_media for delete to authenticated using (false);
revoke all privileges on table public.storefront_media from public;
revoke all privileges on table public.storefront_media from anon;
revoke all privileges on table public.storefront_media from authenticated;

-- ----------------------------------------------------------------------------
-- 5. restaurant_storefront_profiles — 1:1 with restaurants (composite FKs per
--    D-012 layer 4). The slug lives HERE (owner decision D4), never on
--    restaurants or organizations. ordering_enabled and delivery_enabled are
--    present but pinned FALSE by CHECK in this slice: the browse-only contract
--    is a database fact, not a UI convention. A later ticket lifts the CHECK.
-- ----------------------------------------------------------------------------
create table public.restaurant_storefront_profiles (
  restaurant_id        uuid        primary key,
  organization_id      uuid        not null references public.organizations (id) on delete restrict,
  storefront_branch_id uuid        not null,
  slug                 text        not null,
  display_name         text        not null,
  tagline              text,
  public_city          text,
  public_address       text,
  public_phone         text,
  primary_color        text        not null default '#13322a',
  accent_color         text        not null default '#e07b2c',
  visual_preset        text        not null default 'dark',
  locale_default       text        not null default 'ar',
  card_mode            text        not null default 'list',
  motion               text        not null default 'full',
  pickup_enabled       boolean     not null default true,
  delivery_enabled     boolean     not null default false,
  ordering_enabled     boolean     not null default false,
  paused_until         timestamptz,
  pause_reason         text,
  opening_hours        jsonb       not null default '{"weekly":[],"exceptions":[]}'::jsonb,
  logo_media_id        uuid,
  hero_media_id        uuid,
  is_published         boolean     not null default false,
  version              integer     not null default 1,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz,
  unique (organization_id, restaurant_id),
  foreign key (organization_id, restaurant_id)
    references public.restaurants (organization_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, storefront_branch_id)
    references public.branches (organization_id, restaurant_id, id) on delete restrict,
  foreign key (organization_id, logo_media_id)
    references public.storefront_media (organization_id, id) on delete restrict,
  foreign key (organization_id, hero_media_id)
    references public.storefront_media (organization_id, id) on delete restrict,
  -- STORAGE grammar (stricter than the request grammar the UI trusts):
  -- lower-case alphanumerics with single hyphens, 3..48 chars, no reserved word.
  constraint restaurant_storefront_profiles_slug_shape check (
    slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'
    and length(slug) between 3 and 48
    and slug not in ('api', 'order', 'admin', 'pos', 'kds', 'kiosk', 'app', 'ar', 'en', 'he', 'www', 's', 'r')
  ),
  constraint restaurant_storefront_profiles_text_caps check (
    length(btrim(display_name)) between 1 and 60
    and (tagline is null or length(tagline) <= 90)
    and (public_city is null or length(public_city) <= 60)
    and (public_address is null or length(public_address) <= 80)
    and (pause_reason is null or length(pause_reason) <= 120)
  ),
  constraint restaurant_storefront_profiles_phone_shape check (
    public_phone is null or public_phone ~ '^(\+[1-9][0-9]{6,14}|0[0-9]{1,2}[- ]?[0-9]{3}[- ]?[0-9]{4})$'
  ),
  constraint restaurant_storefront_profiles_colours check (
    primary_color ~ '^#[0-9A-Fa-f]{6}$' and accent_color ~ '^#[0-9A-Fa-f]{6}$'
  ),
  constraint restaurant_storefront_profiles_enums check (
    visual_preset in ('dark', 'light')
    and locale_default in ('ar', 'he', 'en')
    and card_mode in ('list', 'grid')
    and motion in ('calm', 'full', 'lively')
  ),
  -- BROWSE-ONLY SLICE: neither flag can be turned on by any path until the
  -- ordering ticket lifts this constraint (owner-visible, reviewable change).
  constraint restaurant_storefront_profiles_browse_only check (
    ordering_enabled = false and delivery_enabled = false
  ),
  constraint restaurant_storefront_profiles_hours_shape check (
    app.storefront_opening_hours_is_valid(opening_hours)
  ),
  constraint restaurant_storefront_profiles_version_positive check (version >= 1)
);

comment on table public.restaurant_storefront_profiles is
  'STOREFRONT-READ-001: the published storefront identity of ONE restaurant (1:1). Owns the public slug (partial-unique among live rows; storage grammar ^[a-z0-9]+(-[a-z0-9]+)*$, 3..48, reserved words refused), the display fields the Storefront renders, the storefront branch, opening hours (jsonb, CHECK-validated), pause state, the two published media references and the publish flag. ordering_enabled / delivery_enabled are pinned FALSE by CHECK in this slice (browse-only). Written only by app.set_restaurant_storefront_profile (manager+ over the restaurant, CAS on version, audited); read by manager+ through app.get_restaurant_storefront_profile and by the public through public.storefront_menu(slug) when is_published and every P0 predicate holds.';

create unique index restaurant_storefront_profiles_slug_live_idx
  on public.restaurant_storefront_profiles (slug)
  where deleted_at is null;

create trigger restaurant_storefront_profiles_set_updated_at
  before update on public.restaurant_storefront_profiles
  for each row execute function app.set_updated_at();

alter table public.restaurant_storefront_profiles enable row level security;
alter table public.restaurant_storefront_profiles force  row level security;
create policy restaurant_storefront_profiles_sel_deny on public.restaurant_storefront_profiles for select to authenticated using (false);
create policy restaurant_storefront_profiles_ins_deny on public.restaurant_storefront_profiles for insert to authenticated with check (false);
create policy restaurant_storefront_profiles_upd_deny on public.restaurant_storefront_profiles for update to authenticated using (false) with check (false);
create policy restaurant_storefront_profiles_del_deny on public.restaurant_storefront_profiles for delete to authenticated using (false);
revoke all privileges on table public.restaurant_storefront_profiles from public;
revoke all privileges on table public.restaurant_storefront_profiles from anon;
revoke all privileges on table public.restaurant_storefront_profiles from authenticated;

-- ----------------------------------------------------------------------------
-- 6. The PUBLIC derivative bucket + write gate. Anonymous GET needs no policy on
--    a public bucket (Storage serves it without RLS); every write is
--    authenticated AND gated on a registered storefront_media row whose
--    restaurant the caller manages — an object can only be uploaded under a key
--    this slice already knows about. A SELECT policy with the SAME gate exists
--    only so that UPDATE / DELETE can find the row (Postgres applies the SELECT
--    policy to them); listing stays denied to everyone else.
-- ----------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('storefront-media', 'storefront-media', true, 524288, array['image/webp'])
on conflict (id) do update
  set name               = excluded.name,
      public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create or replace function app.can_write_storefront_media(p_org uuid, p_restaurant uuid)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  -- GUC-free (D-033 pattern): the caller's highest ACTIVE membership rank that
  -- covers the restaurant; manager+ (rank >= 2) may publish/unpublish media.
  select app.actor_rank_in_scope(p_org, p_restaurant, null) >= 2;
$$;

comment on function app.can_write_storefront_media(uuid, uuid) is
  'STOREFRONT-READ-001: true when the current caller holds an ACTIVE org_owner / restaurant_owner / manager membership covering the restaurant (GUC-free via app.actor_rank_in_scope). Gates every policy on the public storefront-media bucket (select/insert/update/delete for authenticated; the select policy only makes update/delete reachable — anonymous GET of a public bucket never consults RLS).';

revoke all on function app.can_write_storefront_media(uuid, uuid) from public;
revoke all on function app.can_write_storefront_media(uuid, uuid) from anon;
grant execute on function app.can_write_storefront_media(uuid, uuid) to authenticated;

-- The storage policy body runs as the CALLER, who holds no privilege on
-- public.storefront_media (RPC-only table), so the row lookup must happen
-- inside a SECURITY DEFINER gate keyed by the object name.
create or replace function app.can_write_storefront_object(p_name text)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select exists (
    select 1 from public.storefront_media sm
     where sm.object_key = p_name
       and app.can_write_storefront_media(sm.organization_id, sm.restaurant_id)
  );
$$;

comment on function app.can_write_storefront_object(text) is
  'STOREFRONT-READ-001: true when the object name is a REGISTERED storefront_media key whose restaurant the caller manages (rank >= 2). An object can only be written under a key this table already knows; a malformed or unregistered name is denied.';

revoke all on function app.can_write_storefront_object(text) from public;
revoke all on function app.can_write_storefront_object(text) from anon;
grant execute on function app.can_write_storefront_object(text) to authenticated;

-- SELECT is required for the UPDATE / DELETE policies to be reachable at all:
-- Postgres applies the SELECT policy to any UPDATE / DELETE that must find the
-- existing row, so without it a manager could never replace or retract a
-- derivative. It is as narrow as the writes (registered keys of a restaurant
-- the caller manages) and does not affect anonymous GET: a public bucket is
-- served by the Storage server without RLS, and listing stays denied to
-- everyone else.
create policy storefront_media_select on storage.objects
  for select to authenticated
  using (
    bucket_id = 'storefront-media'
    and app.can_write_storefront_object(name)
  );

create policy storefront_media_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'storefront-media'
    and app.can_write_storefront_object(name)
  );

create policy storefront_media_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'storefront-media'
    and app.can_write_storefront_object(name)
  )
  with check (
    bucket_id = 'storefront-media'
    and app.can_write_storefront_object(name)
  );

create policy storefront_media_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'storefront-media'
    and app.can_write_storefront_object(name)
  );

-- ----------------------------------------------------------------------------
-- 7a. Publish preconditions, factored so the writer and the reader agree.
--     Returns the ORDERED list of blockers (empty = publishable).
-- ----------------------------------------------------------------------------
create or replace function app.storefront_publish_blockers(
  p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid, p_slug text, p_hours jsonb)
  returns text[]
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_out      text[] := '{}';
  v_tz       text;
  v_currency text;
  v_tax_on   boolean;
  v_tax_mode text;
begin
  if p_slug is null then v_out := array_append(v_out, 'slug_missing'); end if;
  if p_branch_id is null then
    v_out := array_append(v_out, 'branch_missing');
  else
    select coalesce(b.timezone, r.timezone), coalesce(r.currency_override, o.default_currency), b.tax_enabled, b.tax_mode
      into v_tz, v_currency, v_tax_on, v_tax_mode
      from public.branches b
      join public.restaurants r on r.id = b.restaurant_id and r.organization_id = b.organization_id
      join public.organizations o on o.id = r.organization_id
     where b.id = p_branch_id and b.organization_id = p_organization_id and b.restaurant_id = p_restaurant_id
       and b.deleted_at is null;
    if not found then
      v_out := array_append(v_out, 'branch_missing');
    else
      if v_tz is null or not exists (select 1 from pg_catalog.pg_timezone_names where name = v_tz) then
        v_out := array_append(v_out, 'timezone_missing');
      end if;
      if v_currency is distinct from 'ILS' then v_out := array_append(v_out, 'currency_not_ils'); end if;
      if v_tax_on and v_tax_mode <> 'exclusive' then v_out := array_append(v_out, 'tax_not_exclusive'); end if;
      if not exists (
        select 1
          from public.menu_items i
          join public.menu_categories c
            on c.organization_id = i.organization_id and c.restaurant_id = p_restaurant_id and c.id = i.menu_category_id
         where i.organization_id = p_organization_id and i.restaurant_id = p_restaurant_id
           and i.is_active and i.deleted_at is null and (i.branch_id is null or i.branch_id = p_branch_id)
           and c.is_active and c.deleted_at is null and (c.branch_id is null or c.branch_id = p_branch_id)
      ) then
        v_out := array_append(v_out, 'no_live_item');
      end if;
    end if;
  end if;
  if p_hours is null or jsonb_array_length(coalesce(p_hours -> 'weekly', '[]'::jsonb)) = 0 then
    v_out := array_append(v_out, 'hours_missing');
  end if;
  return v_out;
end;
$$;

comment on function app.storefront_publish_blockers(uuid, uuid, uuid, text, jsonb) is
  'STOREFRONT-READ-001: the ordered publish preconditions (slug set; storefront branch live; timezone resolvable — the pilot NULL->UTC bug; currency ILS; tax exclusive or disabled; >= 1 live category with >= 1 live item at the branch; >= 1 weekly window). Empty = publishable. Shared by the writer (refuses) and the manager read (reports).';

-- Caller-blind SECURITY DEFINER helper: it is only ever called by the two
-- DEFINER RPCs below, which have already verified the caller. Explicitly
-- revoked from every app role (not merely ungranted) so a default-ACL stamp
-- can never expose it.
revoke all on function app.storefront_publish_blockers(uuid, uuid, uuid, text, jsonb) from public;
revoke all on function app.storefront_publish_blockers(uuid, uuid, uuid, text, jsonb) from anon;
revoke all on function app.storefront_publish_blockers(uuid, uuid, uuid, text, jsonb) from authenticated;

-- ----------------------------------------------------------------------------
-- 7b. app.set_restaurant_storefront_profile — the ONLY writer of the profile.
--     House form 20260801090000 (receipt logo): auth -> input -> named-role gate
--     (rank >= manager covering the restaurant; denial audited, no state leak)
--     -> lock restaurant + profile rows -> idempotent replay -> compare-and-set
--     on version (stale => typed version_conflict carrying the current state,
--     no ledger claim) -> validate the patch (typed `invalid` + reason) ->
--     publish preconditions -> claim -> upsert -> audit settings.storefront.updated.
-- ----------------------------------------------------------------------------
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

comment on function app.set_restaurant_storefront_profile(uuid, uuid, uuid, integer, jsonb) is
  'STOREFRONT-READ-001 (D-011/D-012/D-013): the ONLY writer of restaurant_storefront_profiles. Named-role gate org_owner/restaurant_owner/manager covering the restaurant (rank>=2; cashier/kitchen/accountant denied + audited; cross-tenant/anonymous 42501 with no state leak). Patch of allowlisted fields only (unknown field => typed invalid); slug storage grammar + reserved words + live uniqueness; media references must be published rows of THIS restaurant; ordering_enabled/delivery_enabled are NOT patchable (browse-only slice). Optimistic compare-and-set on version (expected 0 creates; stale => typed version_conflict with current state, no ledger claim). Publishing refused with the ordered blocker list until every precondition holds. Idempotent per (actor, client_request_id). Full before/after audit settings.storefront.updated. No money (D-007).';

create or replace function public.set_restaurant_storefront_profile(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid, p_expected_version integer, p_patch jsonb)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.set_restaurant_storefront_profile(p_client_request_id, p_organization_id, p_restaurant_id, p_expected_version, p_patch); $$;

revoke all on function app.set_restaurant_storefront_profile(uuid, uuid, uuid, integer, jsonb)    from public;
revoke all on function app.set_restaurant_storefront_profile(uuid, uuid, uuid, integer, jsonb)    from anon;
grant execute on function app.set_restaurant_storefront_profile(uuid, uuid, uuid, integer, jsonb) to authenticated;
revoke all on function public.set_restaurant_storefront_profile(uuid, uuid, uuid, integer, jsonb)    from public;
revoke all on function public.set_restaurant_storefront_profile(uuid, uuid, uuid, integer, jsonb)    from anon;
grant execute on function public.set_restaurant_storefront_profile(uuid, uuid, uuid, integer, jsonb) to authenticated;

-- ----------------------------------------------------------------------------
-- 7c. app.get_restaurant_storefront_profile — Dashboard read (manager+ covering
--     the restaurant). Returns the row (or exists=false with the defaults the
--     writer would apply), the derived facts the editor needs (timezone,
--     currency, tax) and the CURRENT publish blockers. Cross-tenant / no
--     covering membership / below manager => not_found (no leak).
-- ----------------------------------------------------------------------------
create or replace function app.get_restaurant_storefront_profile(p_organization_id uuid, p_restaurant_id uuid)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = ''
as $$
declare
  v_actor    uuid := app.current_app_user_id();
  v_rank     integer;
  v_p        public.restaurant_storefront_profiles%rowtype;
  v_exists   boolean;
  v_branch   uuid;
  v_tz       text;
  v_currency text;
  v_tax      jsonb;
  v_blockers text[];
  c_entity constant text := 'restaurant_storefront_profile';
begin
  if v_actor is null then
    raise exception 'get_restaurant_storefront_profile: authentication required' using errcode = '42501';
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
  select * into v_p from public.restaurant_storefront_profiles p
   where p.restaurant_id = p_restaurant_id and p.organization_id = p_organization_id and p.deleted_at is null;
  v_exists := found;
  v_branch := case when v_exists then v_p.storefront_branch_id else null end;
  if v_branch is not null then
    select coalesce(b.timezone, r.timezone), coalesce(r.currency_override, o.default_currency),
           jsonb_build_object('enabled', b.tax_enabled, 'rate_bp', b.tax_rate_bp, 'mode', b.tax_mode)
      into v_tz, v_currency, v_tax
      from public.branches b
      join public.restaurants r on r.id = b.restaurant_id and r.organization_id = b.organization_id
      join public.organizations o on o.id = r.organization_id
     where b.id = v_branch and b.organization_id = p_organization_id and b.restaurant_id = p_restaurant_id;
  end if;
  v_blockers := app.storefront_publish_blockers(p_organization_id, p_restaurant_id, v_branch,
                  case when v_exists then v_p.slug else null end,
                  case when v_exists then v_p.opening_hours else null end);
  return jsonb_build_object(
    'ok', true, 'entity', c_entity, 'restaurant_id', p_restaurant_id,
    'exists', v_exists,
    'version', case when v_exists then v_p.version else 0 end,
    'profile', case when v_exists then to_jsonb(v_p) - 'organization_id' - 'deleted_at' else null end,
    'derived', jsonb_build_object(
      'timezone', v_tz, 'currency_code', v_currency, 'tax', v_tax,
      'publish_ready', coalesce(array_length(v_blockers, 1), 0) = 0,
      'publish_blockers', to_jsonb(v_blockers),
      'media_prefix', app.storefront_media_prefix(p_restaurant_id)));
end;
$$;

comment on function app.get_restaurant_storefront_profile(uuid, uuid) is
  'STOREFRONT-READ-001: Dashboard read of the storefront profile for manager+ (rank>=2) covering the restaurant; below-manager, cross-tenant and unknown restaurant all return not_found (no leak). Carries the derived timezone/currency/tax facts, the current publish blockers and the opaque media prefix the publish action must upload under.';

create or replace function public.get_restaurant_storefront_profile(p_organization_id uuid, p_restaurant_id uuid)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.get_restaurant_storefront_profile(p_organization_id, p_restaurant_id); $$;

revoke all on function app.get_restaurant_storefront_profile(uuid, uuid)    from public;
revoke all on function app.get_restaurant_storefront_profile(uuid, uuid)    from anon;
grant execute on function app.get_restaurant_storefront_profile(uuid, uuid) to authenticated;
revoke all on function public.get_restaurant_storefront_profile(uuid, uuid)    from public;
revoke all on function public.get_restaurant_storefront_profile(uuid, uuid)    from anon;
grant execute on function public.get_restaurant_storefront_profile(uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 8. public.storefront_menu(p_slug text) — THE public read contract.
--    SECURITY DEFINER in `public` by explicit enumeration (D-037 amendment,
--    owner decision D1): `anon` has no USAGE on `app`, so the house
--    INVOKER-wrapper-over-app.* form dead-ends for it; the function itself is
--    the boundary. It resolves scope from the slug only and calls NO membership
--    or identity helper. Live predicates are copied VERBATIM from app.kiosk_menu
--    (20260821090000:505-600); the projection is narrower than the kiosk's.
-- ----------------------------------------------------------------------------
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

comment on function public.storefront_menu(text) is
  'STOREFRONT-READ-001 (D-037 as amended, T-016/T-017): THE anon-only public read of one published storefront. Input = slug only (request grammar ^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$). Uniform {ok:false,error:not_found} for invalid/unknown/unpublished/suspended/deleted/NULL-timezone/non-ILS/inclusive-tax (anti-oracle); typed payload_limit above 100/500/2000/8000. Serves display fields, today''s window + open_now in the branch timezone, service state (paused/open/closed; ordering_enabled ALWAYS false in this slice), tax {enabled,rate_bp,mode}, live categories/items/modifiers/options with the kiosk_menu predicates, sold-out from the branch availability, image/logo/hero URL PATHS only for PUBLISHED derivatives. Never serves sku/prep/kitchen/attributes/station/item_type/sizes/variants/kitchen_meat/quantity rules/private keys/any UUID of org, restaurant, branch or device. SECURITY DEFINER by enumeration; calls no membership or identity helper; EXECUTE = anon only (authenticated explicitly revoked; service_role keeps the platform-stamped grant).';

-- THE grant set. Explicit `revoke ... from authenticated` because the hosted
-- postgres default ACL in `public` stamps authenticated=X at CREATE time and a
-- PUBLIC revoke does not remove an explicit grant (the SEC-001 lesson).
revoke all on function public.storefront_menu(text) from public;
revoke all on function public.storefront_menu(text) from anon;
revoke all on function public.storefront_menu(text) from authenticated;
grant execute on function public.storefront_menu(text) to anon;

-- The helpers this function runs as its owner are never granted to app roles
-- (explicit revokes from authenticated too: their only callers are DEFINER
-- functions owned by postgres, and the CHECK constraints that use two of them
-- are only ever evaluated inside those DEFINER writers).
revoke all on function app.storefront_opening_hours_is_valid(jsonb)                 from public;
revoke all on function app.storefront_opening_hours_is_valid(jsonb)                 from anon;
revoke all on function app.storefront_opening_hours_is_valid(jsonb)                 from authenticated;
revoke all on function app.storefront_service_window(jsonb, text, timestamptz)      from public;
revoke all on function app.storefront_service_window(jsonb, text, timestamptz)      from anon;
revoke all on function app.storefront_service_window(jsonb, text, timestamptz)      from authenticated;
revoke all on function app.storefront_media_prefix(uuid)                            from public;
revoke all on function app.storefront_media_prefix(uuid)                            from anon;
revoke all on function app.storefront_media_prefix(uuid)                            from authenticated;

-- ----------------------------------------------------------------------------
-- 9. Assert the posture this file establishes; abort the transaction otherwise
--    (so hosted can never end up half-applied).
-- ----------------------------------------------------------------------------
do $$
declare
  v_anon_set text;
  v_defs     text;
begin
  select coalesce(string_agg(regexp_replace(p.oid::regprocedure::text, '^public.', ''), ', ' order by regexp_replace(p.oid::regprocedure::text, '^public.', '')), '')
    into v_anon_set
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
     and has_function_privilege('anon', p.oid, 'EXECUTE');
  if v_anon_set <> 'storefront_menu(text)' then
    raise exception 'STOREFRONT-READ-001 posture NOT reached: anon-executable public set is [%], expected exactly storefront_menu(text)', v_anon_set;
  end if;
  if has_function_privilege('authenticated', 'public.storefront_menu(text)', 'EXECUTE') then
    raise exception 'STOREFRONT-READ-001 posture NOT reached: authenticated still holds EXECUTE on public.storefront_menu(text)';
  end if;
  select coalesce(string_agg(regexp_replace(p.oid::regprocedure::text, '^public.', ''), ', ' order by regexp_replace(p.oid::regprocedure::text, '^public.', '')), '')
    into v_defs
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p') and p.prosecdef;
  if v_defs <> 'storefront_menu(text)' then
    raise exception 'STOREFRONT-READ-001 posture NOT reached: public SECURITY DEFINER set is [%], expected exactly storefront_menu(text)', v_defs;
  end if;
  if has_schema_privilege('anon', 'app', 'USAGE') then
    raise exception 'STOREFRONT-READ-001 invariant broken: anon has USAGE on schema app';
  end if;
  raise notice 'STOREFRONT-READ-001 posture reached: anon allowlist = {storefront_menu(text)}, authenticated revoked on it, public DEFINER set = {storefront_menu(text)}';
end
$$;

-- ----------------------------------------------------------------------------
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop function if exists public.storefront_menu(text);
--   drop function if exists public.get_restaurant_storefront_profile(uuid, uuid);
--   drop function if exists app.get_restaurant_storefront_profile(uuid, uuid);
--   drop function if exists public.set_restaurant_storefront_profile(uuid, uuid, uuid, integer, jsonb);
--   drop function if exists app.set_restaurant_storefront_profile(uuid, uuid, uuid, integer, jsonb);
--   drop function if exists app.storefront_publish_blockers(uuid, uuid, uuid, text, jsonb);
--   drop policy if exists storefront_media_insert on storage.objects;
--   drop policy if exists storefront_media_update on storage.objects;
--   drop policy if exists storefront_media_delete on storage.objects;
--   drop function if exists app.can_write_storefront_object(text);
--   drop function if exists app.can_write_storefront_media(uuid, uuid);
--   delete from storage.buckets where id = 'storefront-media';   -- objects first
--   drop table if exists public.restaurant_storefront_profiles;
--   drop table if exists public.storefront_media;
--   drop function if exists app.storefront_media_prefix(uuid);
--   drop function if exists app.storefront_service_window(jsonb, text, timestamptz);
--   drop function if exists app.storefront_opening_hours_is_valid(jsonb);
-- ----------------------------------------------------------------------------
