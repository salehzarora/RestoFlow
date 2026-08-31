-- ============================================================================
-- ADMIN-126B — SECURE, AUDITED, READ-ONLY PLATFORM SUPPORT ACCESS.
--
-- "Open Dashboard" for a support operator, without asking a restaurant owner
-- for their password and without becoming them.
--
-- WHAT THIS IS NOT
--   * NOT a login bypass — no owner credential is read, reset or minted.
--   * NOT impersonation — app.current_app_user_id() keeps resolving to the
--     PLATFORM ADMIN for the whole session, so every audit row and every
--     actor stamp names the operator.
--   * NOT a membership — nothing is ever written to public.memberships.
--
-- WHY THE READS ARE LISTED ONE BY ONE
-- -----------------------------------
-- ADMIN-126 established that the Dashboard reads through SECURITY DEFINER RPCs,
-- and that those RPCs gate on app.actor_rank_in_scope — the SAME helper that
-- gates writes. Widening it would grant writes with it.
--
-- So this migration does NOT widen it. It adds a parallel READ-ONLY rank,
-- app.actor_read_rank_in_scope, and switches exactly FIFTEEN named read RPCs
-- onto it. app.actor_rank_in_scope keeps its old meaning and its old value, and
-- every one of the 21 mutating Dashboard RPCs, both domain guards
-- (menu_guard / printer_guard), the PIN path and the device path are untouched.
-- A support operator therefore ranks ZERO everywhere a write is authorized.
--
-- It also does NOT touch app.current_org_id, app.has_scope or
-- app.has_role_in_scope: the earlier draft extended those RLS SELECT helpers,
-- which the real client never exercises. Leaving them alone means this
-- migration changes no tenant policy at all.
--
-- THE APPROVED READ SURFACE (15), and why each is here:
--   identity/context   list_org_structure
--   catalog            list_menu
--   reporting          owner_report_range, owner_daily_report, sales_summary,
--                      owner_sales_series, owner_top_items,
--                      owner_report_currency_breakdown
--   settings           get_branch_kitchen_workflow_mode,
--                      get_branch_pos_shift_close_enabled,
--                      list_quick_note_presets
--   hardware           list_printers, list_devices
--   layout             list_tables
--   branding           get_restaurant_receipt_logo
--
-- DELIBERATELY WITHHELD, because a support operator does not need a person's
-- identity to answer "is this tenant set up correctly and what did it sell":
--   list_staff, list_members            staff names and emails
--   owner_order_history, _detail,
--   owner_active_orders                 carry customer_name AND customer_phone
--   owner_audit_events                  names staff actors
--   sync_push / sync_pull               PIN/device bearer paths; a browser
--                                       support session has neither
--
-- THE HANDOFF
--   start    -> 32 CSPRNG bytes; only the SHA-256 hash is stored, the plaintext
--               is returned ONCE and never persisted.
--   exchange -> one-time, ~60s window, re-checks grant + aal2 AT EXCHANGE TIME.
--   session  -> 15-minute server TTL, re-evaluated on every single read.
--   end      -> explicit, audited, and immediate.
--
-- No credential, access token, refresh token or TOTP material is stored here.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. The session record
-- ----------------------------------------------------------------------------
create table if not exists public.platform_support_sessions (
  id                          uuid primary key default extensions.gen_random_uuid(),
  platform_admin_app_user_id  uuid        not null references public.app_users(id) on delete restrict,
  target_organization_id      uuid        not null references public.organizations(id) on delete restrict,
  target_restaurant_id        uuid        null     references public.restaurants(id)   on delete restrict,
  reason                      text        not null,
  status                      text        not null default 'pending',
  expires_at                  timestamptz not null,
  created_at                  timestamptz not null default now(),
  ended_at                    timestamptz null,
  -- ONLY the hash. The plaintext handoff is returned to the operator once and
  -- is never written down, so a database disclosure cannot be replayed into a
  -- tenant session.
  token_hash                  text        not null,
  token_consumed_at           timestamptz null,
  constraint platform_support_sessions_reason_present check (btrim(reason) <> ''),
  constraint platform_support_sessions_status_valid  check (status in ('pending', 'active', 'ended')),
  constraint platform_support_sessions_token_hash_unique unique (token_hash)
);

comment on table public.platform_support_sessions is
  'ADMIN-126B short-lived, audited, READ-ONLY platform support sessions. Stores a '
  'SHA-256 token hash only — never the plaintext token and never any credential. '
  'Grants no membership: the operator remains the actor throughout.';

create index if not exists platform_support_sessions_admin_active_idx
  on public.platform_support_sessions (platform_admin_app_user_id, status, expires_at desc);
create index if not exists platform_support_sessions_target_idx
  on public.platform_support_sessions (target_organization_id, created_at desc);

-- Platform plane, exactly like platform_admin_grants: RLS on and FORCED with NO
-- policy at all, so the tenant path is denied by default-deny rather than by a
-- predicate someone could widen later. No grants to anon or authenticated; the
-- only way in is the SECURITY DEFINER functions below.
alter table public.platform_support_sessions enable row level security;
alter table public.platform_support_sessions force row level security;
revoke all on table public.platform_support_sessions from public;
revoke all on table public.platform_support_sessions from anon;
revoke all on table public.platform_support_sessions from authenticated;

-- ----------------------------------------------------------------------------
-- 2. Tunables, in one place
-- ----------------------------------------------------------------------------
create or replace function app.platform_support_ttl_minutes()
  returns integer language sql immutable set search_path = '' as $$ select 15 $$;

create or replace function app.platform_support_exchange_seconds()
  returns integer language sql immutable set search_path = '' as $$ select 60 $$;

-- ----------------------------------------------------------------------------
-- 3. Resolver — the caller's live support session, if any
-- ----------------------------------------------------------------------------
create or replace function app.current_support_session()
  returns uuid
  language sql
  stable
  security definer
  set search_path = ''
as $$
  -- ACTIVE means: exchanged (token consumed), not ended, and not past its TTL.
  -- Expiry is evaluated HERE, on every call, rather than by a sweeper — so a
  -- stale row can never behave as if it were live.
  select s.id
    from public.platform_support_sessions s
   where s.platform_admin_app_user_id = app.current_app_user_id()
     and s.status            = 'active'
     and s.token_consumed_at is not null
     and s.expires_at        > now()
   order by s.expires_at desc
   limit 1
$$;

-- ----------------------------------------------------------------------------
-- 4. THE central support-read guard
--
-- Every approved read consults this and only this. It answers one question:
-- may the caller READ this exact scope right now? It never returns a rank, never
-- touches a membership, and has no write meaning anywhere in the system.
-- ----------------------------------------------------------------------------
create or replace function app.platform_support_can_read_scope(
  p_organization_id uuid,
  p_restaurant_id   uuid default null,
  p_branch_id       uuid default null
)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select exists (
    select 1
    from public.platform_support_sessions s
    where s.id = app.current_support_session()
      -- the session names ONE organization and grants nothing outside it
      and s.target_organization_id = p_organization_id
      and p_organization_id is not null
      -- if the session was scoped to a restaurant, it does not reach another
      and (s.target_restaurant_id is null
           or p_restaurant_id is null
           or s.target_restaurant_id = p_restaurant_id)
  )
$$;

comment on function app.platform_support_can_read_scope(uuid, uuid, uuid) is
  'ADMIN-126B: may the caller READ this scope under a live support session? '
  'Read-only by construction — it yields no rank and no role, and no write path '
  'consults it.';

-- ----------------------------------------------------------------------------
-- 5. The parallel READ rank
--
-- app.actor_rank_in_scope is left EXACTLY as it was, because every write gate in
-- the system is built on it. This sibling is what the fifteen approved READ RPCs
-- use instead: a member ranks as before, and a support operator — who ranks 0
-- there and will keep ranking 0 there — reads at owner level HERE ONLY.
-- ----------------------------------------------------------------------------
create or replace function app.actor_read_rank_in_scope(
  p_organization_id uuid,
  p_restaurant_id   uuid default null,
  p_branch_id       uuid default null
)
  returns integer
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select greatest(
    app.actor_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id),
    case when app.platform_support_can_read_scope(p_organization_id, p_restaurant_id, p_branch_id)
         then app.role_rank('org_owner') else 0 end
  )
$$;

comment on function app.actor_read_rank_in_scope(uuid, uuid, uuid) is
  'ADMIN-126B: READ-ONLY companion to app.actor_rank_in_scope. Used by the '
  'fifteen approved support-readable RPCs and by nothing that writes.';

-- ----------------------------------------------------------------------------
-- 6. Start — mint a one-time handoff
-- ----------------------------------------------------------------------------
create or replace function app.platform_admin_start_support_session(
  p_organization_id uuid,
  p_restaurant_id   uuid default null,
  p_reason          text default null
)
  returns jsonb
  language plpgsql
  volatile
  security definer
  set search_path = ''
as $$
declare
  v_actor   uuid;
  v_token   text;
  v_id      uuid;
  v_org     public.organizations%rowtype;
  v_rest    public.restaurants%rowtype;
  v_expires timestamptz;
begin
  v_actor := app.platform_admin_guard(p_reason);

  select * into v_org from public.organizations
   where id = p_organization_id and deleted_at is null;
  if not found then
    -- Same code as a denial: this must not become a way to discover which
    -- organization ids exist.
    raise exception 'platform support: no such organization, or access denied'
      using errcode = '42501';
  end if;

  if p_restaurant_id is not null then
    select * into v_rest from public.restaurants
     where id = p_restaurant_id
       and organization_id = p_organization_id
       and deleted_at is null;
    if not found then
      raise exception 'platform support: no such restaurant in that organization'
        using errcode = '42501';
    end if;
  end if;

  -- Any earlier live session for this operator is ended first: one operator,
  -- one tenant at a time, so a stale session for tenant A cannot still be open
  -- while they support tenant B.
  update public.platform_support_sessions
     set status = 'ended', ended_at = now()
   where platform_admin_app_user_id = v_actor
     and status <> 'ended';

  v_expires := now() + (app.platform_support_ttl_minutes() || ' minutes')::interval;
  -- 32 bytes of CSPRNG. Only the hash is stored; this plaintext exists nowhere
  -- on the server after this function returns.
  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  insert into public.platform_support_sessions
    (platform_admin_app_user_id, target_organization_id, target_restaurant_id,
     reason, status, expires_at, token_hash)
  values
    (v_actor, p_organization_id, p_restaurant_id, btrim(p_reason), 'pending', v_expires,
     encode(extensions.digest(v_token, 'sha256'), 'hex'))
  returning id into v_id;

  insert into public.platform_admin_audit_events
    (actor_app_user_id, target_organization_id, action, reason, details)
  values
    (v_actor, p_organization_id, 'platform.support.start', btrim(p_reason),
     jsonb_build_object('support_session_id', v_id,
                        'target_restaurant_id', p_restaurant_id,
                        'expires_at', v_expires));

  return jsonb_build_object(
    'ok', true,
    'support_session_id', v_id,
    -- Returned ONCE. No read path can produce it again.
    'handoff_token', v_token,
    'exchange_expires_at', now() + (app.platform_support_exchange_seconds() || ' seconds')::interval,
    'expires_at', v_expires,
    'organization', jsonb_build_object('id', v_org.id, 'name', v_org.name),
    'restaurant', case when v_rest.id is null then 'null'::jsonb
                       else jsonb_build_object('id', v_rest.id, 'name', v_rest.name) end,
    'server_ts', now());
end;
$$;

-- ----------------------------------------------------------------------------
-- 7. Exchange — one time, then never again
-- ----------------------------------------------------------------------------
create or replace function app.platform_support_exchange(p_token text)
  returns jsonb
  language plpgsql
  volatile
  security definer
  set search_path = ''
as $$
declare
  v_actor uuid := app.current_app_user_id();
  v_row   public.platform_support_sessions%rowtype;
  v_org   public.organizations%rowtype;
  v_rest  public.restaurants%rowtype;
begin
  if v_actor is null then
    raise exception 'platform support: authentication required' using errcode = '42501';
  end if;
  if coalesce(btrim(p_token), '') = '' then
    raise exception 'platform support: this handoff is not valid' using errcode = '42501';
  end if;

  -- Matched by HASH, and locked so two concurrent exchanges of one token cannot
  -- both win.
  select * into v_row
    from public.platform_support_sessions
   where token_hash = encode(extensions.digest(btrim(p_token), 'sha256'), 'hex')
   for update;

  -- Every failure below raises the SAME error on purpose: an attacker must not
  -- be able to tell "wrong token" from "already used" from "expired".
  if not found
     or v_row.platform_admin_app_user_id <> v_actor
     or v_row.status <> 'pending'
     or v_row.token_consumed_at is not null
     or v_row.expires_at <= now()
     or v_row.created_at + (app.platform_support_exchange_seconds() || ' seconds')::interval < now()
     -- re-checked AT EXCHANGE TIME: a grant revoked or an MFA level lost between
     -- start and exchange must close the door.
     or not app.is_platform_admin()
     or app.current_auth_assurance_level() is distinct from 'aal2'
  then
    raise exception 'platform support: this handoff is not valid' using errcode = '42501';
  end if;

  update public.platform_support_sessions
     set status = 'active', token_consumed_at = now()
   where id = v_row.id;

  select * into v_org  from public.organizations where id = v_row.target_organization_id;
  if v_row.target_restaurant_id is not null then
    select * into v_rest from public.restaurants where id = v_row.target_restaurant_id;
  end if;

  insert into public.platform_admin_audit_events
    (actor_app_user_id, target_organization_id, action, reason, details)
  values
    (v_actor, v_row.target_organization_id, 'platform.support.exchange', v_row.reason,
     jsonb_build_object('support_session_id', v_row.id));

  return jsonb_build_object(
    'ok', true,
    'support_session_id', v_row.id,
    'reason', v_row.reason,
    'expires_at', v_row.expires_at,
    'read_only', true,
    'organization', jsonb_build_object('id', v_org.id, 'name', v_org.name),
    'restaurant', case when v_rest.id is null then 'null'::jsonb
                       else jsonb_build_object('id', v_rest.id, 'name', v_rest.name) end,
    'server_ts', now());
end;
$$;

-- ----------------------------------------------------------------------------
-- 8. Status + end
-- ----------------------------------------------------------------------------
create or replace function app.platform_support_current()
  returns jsonb
  language plpgsql
  volatile              -- it appends one audit row per polled read
  security definer
  set search_path = ''
as $$
declare
  v_row  public.platform_support_sessions%rowtype;
  v_org  public.organizations%rowtype;
  v_rest public.restaurants%rowtype;
begin
  select * into v_row from public.platform_support_sessions
   where id = app.current_support_session();
  if not found then
    -- Not an error: "no support session" is the ordinary tenant answer, and the
    -- Dashboard asks this on every boot.
    return jsonb_build_object('ok', true, 'active', false, 'server_ts', now());
  end if;
  select * into v_org from public.organizations where id = v_row.target_organization_id;
  if v_row.target_restaurant_id is not null then
    select * into v_rest from public.restaurants where id = v_row.target_restaurant_id;
  end if;

  insert into public.platform_admin_audit_events
    (actor_app_user_id, target_organization_id, action, reason, details)
  values
    (v_row.platform_admin_app_user_id, v_row.target_organization_id,
     'platform.support.read.dashboard', v_row.reason,
     jsonb_build_object('support_session_id', v_row.id));

  return jsonb_build_object(
    'ok', true,
    'active', true,
    'support_session_id', v_row.id,
    'reason', v_row.reason,
    'expires_at', v_row.expires_at,
    'read_only', true,
    'organization', jsonb_build_object('id', v_org.id, 'name', v_org.name),
    'restaurant', case when v_rest.id is null then 'null'::jsonb
                       else jsonb_build_object('id', v_rest.id, 'name', v_rest.name) end,
    'server_ts', now());
end;
$$;

create or replace function app.platform_support_end(p_support_session_id uuid default null)
  returns jsonb
  language plpgsql
  volatile
  security definer
  set search_path = ''
as $$
declare
  v_actor uuid := app.current_app_user_id();
  v_id    uuid := coalesce(p_support_session_id, app.current_support_session());
  v_row   public.platform_support_sessions%rowtype;
begin
  if v_actor is null then
    raise exception 'platform support: authentication required' using errcode = '42501';
  end if;
  if v_id is null then
    return jsonb_build_object('ok', true, 'ended', false, 'server_ts', now());
  end if;

  -- Only the operator who started it may end it.
  update public.platform_support_sessions
     set status = 'ended', ended_at = now()
   where id = v_id
     and platform_admin_app_user_id = v_actor
     and status <> 'ended'
  returning * into v_row;

  if not found then
    return jsonb_build_object('ok', true, 'ended', false, 'server_ts', now());
  end if;

  insert into public.platform_admin_audit_events
    (actor_app_user_id, target_organization_id, action, reason, details)
  values
    (v_actor, v_row.target_organization_id, 'platform.support.end', v_row.reason,
     jsonb_build_object('support_session_id', v_row.id));

  return jsonb_build_object('ok', true, 'ended', true,
                            'support_session_id', v_row.id, 'server_ts', now());
end;
$$;

-- ----------------------------------------------------------------------------
-- 9. Thin public SECURITY INVOKER wrappers
--
-- No new PARAMETER is added to any existing RPC and no overload is created: the
-- session is resolved from the CALLER, so PostgREST sees exactly the signatures
-- it saw before and there is no ambiguity to resolve.
-- ----------------------------------------------------------------------------
create or replace function public.platform_admin_start_support_session(
  p_organization_id uuid, p_restaurant_id uuid default null, p_reason text default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.platform_admin_start_support_session(p_organization_id, p_restaurant_id, p_reason); $$;

create or replace function public.platform_support_exchange(p_token text)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.platform_support_exchange(p_token); $$;

create or replace function public.platform_support_current()
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.platform_support_current(); $$;

create or replace function public.platform_support_end(p_support_session_id uuid default null)
  returns jsonb language sql security invoker set search_path = ''
as $$ select app.platform_support_end(p_support_session_id); $$;

-- ----------------------------------------------------------------------------
-- 10. Grants — both layers to authenticated; PUBLIC *and* anon revoked
-- ----------------------------------------------------------------------------
revoke all on function app.platform_admin_start_support_session(uuid, uuid, text) from public;
revoke all on function app.platform_admin_start_support_session(uuid, uuid, text) from anon;
revoke all on function app.platform_support_exchange(text)                        from public;
revoke all on function app.platform_support_exchange(text)                        from anon;
revoke all on function app.platform_support_current()                             from public;
revoke all on function app.platform_support_current()                             from anon;
revoke all on function app.platform_support_end(uuid)                             from public;
revoke all on function app.platform_support_end(uuid)                             from anon;
revoke all on function app.current_support_session()                              from public;
revoke all on function app.current_support_session()                              from anon;
revoke all on function app.platform_support_can_read_scope(uuid, uuid, uuid)      from public;
revoke all on function app.platform_support_can_read_scope(uuid, uuid, uuid)      from anon;
revoke all on function app.actor_read_rank_in_scope(uuid, uuid, uuid)             from public;
revoke all on function app.actor_read_rank_in_scope(uuid, uuid, uuid)             from anon;
revoke all on function app.platform_support_ttl_minutes()                         from public;
revoke all on function app.platform_support_ttl_minutes()                         from anon;
revoke all on function app.platform_support_exchange_seconds()                    from public;
revoke all on function app.platform_support_exchange_seconds()                    from anon;

revoke all on function public.platform_admin_start_support_session(uuid, uuid, text) from public;
revoke all on function public.platform_admin_start_support_session(uuid, uuid, text) from anon;
revoke all on function public.platform_support_exchange(text)                        from public;
revoke all on function public.platform_support_exchange(text)                        from anon;
revoke all on function public.platform_support_current()                             from public;
revoke all on function public.platform_support_current()                             from anon;
revoke all on function public.platform_support_end(uuid)                             from public;
revoke all on function public.platform_support_end(uuid)                             from anon;

grant execute on function app.platform_admin_start_support_session(uuid, uuid, text) to authenticated;
grant execute on function app.platform_support_exchange(text)                        to authenticated;
grant execute on function app.platform_support_current()                             to authenticated;
grant execute on function app.platform_support_end(uuid)                             to authenticated;
grant execute on function public.platform_admin_start_support_session(uuid, uuid, text) to authenticated;
grant execute on function public.platform_support_exchange(text)                        to authenticated;
grant execute on function public.platform_support_current()                             to authenticated;
grant execute on function public.platform_support_end(uuid)                             to authenticated;

-- app.current_support_session / _can_read_scope / actor_read_rank_in_scope are
-- consulted only from inside SECURITY DEFINER functions, so `authenticated`
-- never needs to call them and is not granted them.

-- ============================================================================
-- 11. THE FIFTEEN APPROVED READ RPCs
--
-- Each is reproduced VERBATIM from the live catalog with exactly one asserted
-- substitution, so nothing else about them can drift. Grants and signatures are
-- unchanged, so no wrapper needs re-granting and PostgREST sees no new overload.
-- ============================================================================

-- ---- list_menu (rank gate) ---------------------------------------------------
CREATE OR REPLACE FUNCTION app.list_menu(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor      uuid := app.current_app_user_id();
  v_rank       integer;
  v_currency   text;
  v_categories jsonb;
  v_items      jsonb;
  v_sizes      jsonb;
  v_variants   jsonb;
  v_modifiers  jsonb;
  v_options    jsonb;
begin
  if v_actor is null then
    raise exception 'list_menu: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null then
    raise exception 'list_menu: organization_id and restaurant_id are required' using errcode = '42501';
  end if;

  -- authority over the PASSED scope (downward-only coverage); 0 => not a covering member.
  v_rank := app.actor_read_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'list_menu: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    -- kitchen_staff/cashier/accountant are excluded from the management view
    -- (consistent with T-003: menu rows carry money and this surface is manager+
    -- only, so no per-row redaction is needed below).
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'menu');
  end if;

  -- structural validation: the restaurant must belong to the org, and the
  -- branch (when passed) must belong to that restaurant (IDOR fail-closed).
  if not exists (select 1 from public.restaurants r
                 where r.id = p_restaurant_id and r.organization_id = p_organization_id) then
    raise exception 'list_menu: restaurant not found in the target organization' using errcode = '42501';
  end if;
  if p_branch_id is not null and not exists (
       select 1 from public.branches b
       where b.id = p_branch_id
         and b.organization_id = p_organization_id
         and b.restaurant_id   = p_restaurant_id) then
    raise exception 'list_menu: branch not found in the target restaurant' using errcode = '42501';
  end if;

  -- the REAL tenant currency: restaurants.currency_override, else the
  -- organization default (so menu writes stop defaulting to USD client-side).
  select coalesce(r.currency_override, o.default_currency)
    into v_currency
    from public.restaurants r
    join public.organizations o on o.id = r.organization_id
    where r.id = p_restaurant_id and r.organization_id = p_organization_id;

  -- Every returned row carries organization_id / restaurant_id / branch_id
  -- (the Dart fromJson factories require the tenant keys on every row; D-001).

  -- categories: tombstone-excluded, INACTIVE INCLUDED (management view);
  -- branch-visible (restaurant-wide branch-null rows + the requested branch).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', c.id, 'organization_id', c.organization_id, 'restaurant_id', c.restaurant_id,
           'branch_id', c.branch_id, 'name', c.name, 'display_order', c.display_order,
           'is_active', c.is_active, 'icon_key', c.icon_key)
           order by c.display_order, c.name), '[]'::jsonb)
    into v_categories
    from public.menu_categories c
    where c.organization_id = p_organization_id
      and c.restaurant_id   = p_restaurant_id
      and c.deleted_at is null
      and (p_branch_id is null or c.branch_id is null or c.branch_id = p_branch_id);

  -- items: same filters; base_price_minor is integer minor bigint (D-007);
  -- NO redaction (manager+ only surface). MVP: + image_path + the six rich
  -- attribute keys (each nullable — the keys are always present so the Dart
  -- parser reads them uniformly).
  -- RESTAURANT-OPERATIONS-V1-001: when a branch is requested, each item
  -- additionally carries its availability override for THAT branch (absent
  -- row = available). With no branch there is no single truthful answer, so
  -- the keys are simply ABSENT (wire-compatible).
  if p_branch_id is not null then
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', i.id, 'organization_id', i.organization_id, 'restaurant_id', i.restaurant_id,
             'branch_id', i.branch_id, 'menu_category_id', i.menu_category_id, 'name', i.name,
             'description', i.description, 'base_price_minor', i.base_price_minor,
             'currency_code', i.currency_code, 'default_station_id', i.default_station_id,
             'display_order', i.display_order, 'is_active', i.is_active,
             'image_path', i.image_path,
             'item_type', i.item_type, 'tags', i.tags, 'prep_minutes', i.prep_minutes,
             'sku', i.sku, 'kitchen_note', i.kitchen_note, 'attributes', i.attributes,
             'availability', coalesce(a.availability, 'available'),
             'availability_reason', a.reason)
             order by i.display_order, i.name), '[]'::jsonb)
      into v_items
      from public.menu_items i
      left join public.menu_item_branch_availability a
        on a.organization_id = i.organization_id
       and a.branch_id       = p_branch_id
       and a.menu_item_id    = i.id
      where i.organization_id = p_organization_id
        and i.restaurant_id   = p_restaurant_id
        and i.deleted_at is null
        and (i.branch_id is null or i.branch_id = p_branch_id);
  else
    select coalesce(jsonb_agg(jsonb_build_object(
             'id', i.id, 'organization_id', i.organization_id, 'restaurant_id', i.restaurant_id,
             'branch_id', i.branch_id, 'menu_category_id', i.menu_category_id, 'name', i.name,
             'description', i.description, 'base_price_minor', i.base_price_minor,
             'currency_code', i.currency_code, 'default_station_id', i.default_station_id,
             'display_order', i.display_order, 'is_active', i.is_active,
             'image_path', i.image_path,
             'item_type', i.item_type, 'tags', i.tags, 'prep_minutes', i.prep_minutes,
             'sku', i.sku, 'kitchen_note', i.kitchen_note, 'attributes', i.attributes)
             order by i.display_order, i.name), '[]'::jsonb)
      into v_items
      from public.menu_items i
      where i.organization_id = p_organization_id
        and i.restaurant_id   = p_restaurant_id
        and i.deleted_at is null;
  end if;

  -- sizes: children of the RETURNED item set (join, tombstone-filtered at
  -- each level, child branch-visible too).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id, 'organization_id', s.organization_id, 'restaurant_id', s.restaurant_id,
           'branch_id', s.branch_id, 'menu_item_id', s.menu_item_id, 'name', s.name,
           'price_delta_minor', s.price_delta_minor,
           'display_order', s.display_order, 'is_active', s.is_active)
           order by s.display_order, s.name), '[]'::jsonb)
    into v_sizes
    from public.item_sizes s
    join public.menu_items i
      on i.organization_id = s.organization_id and i.id = s.menu_item_id
     and i.restaurant_id = p_restaurant_id
     and i.deleted_at is null
     and (p_branch_id is null or i.branch_id is null or i.branch_id = p_branch_id)
    where s.organization_id = p_organization_id
      and s.restaurant_id   = p_restaurant_id
      and s.deleted_at is null
      and (p_branch_id is null or s.branch_id is null or s.branch_id = p_branch_id);

  -- variants: same shape/filters as sizes.
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', v.id, 'organization_id', v.organization_id, 'restaurant_id', v.restaurant_id,
           'branch_id', v.branch_id, 'menu_item_id', v.menu_item_id, 'name', v.name,
           'price_delta_minor', v.price_delta_minor,
           'display_order', v.display_order, 'is_active', v.is_active)
           order by v.display_order, v.name), '[]'::jsonb)
    into v_variants
    from public.item_variants v
    join public.menu_items i
      on i.organization_id = v.organization_id and i.id = v.menu_item_id
     and i.restaurant_id = p_restaurant_id
     and i.deleted_at is null
     and (p_branch_id is null or i.branch_id is null or i.branch_id = p_branch_id)
    where v.organization_id = p_organization_id
      and v.restaurant_id   = p_restaurant_id
      and v.deleted_at is null
      and (p_branch_id is null or v.branch_id is null or v.branch_id = p_branch_id);

  -- modifiers: children of the RETURNED item set. MVP: + allow_quantity /
  -- max_quantity (COUNT settings, never money — D-007).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', m.id, 'organization_id', m.organization_id, 'restaurant_id', m.restaurant_id,
           'branch_id', m.branch_id, 'menu_item_id', m.menu_item_id, 'name', m.name,
           'selection_type', m.selection_type, 'min_select', m.min_select,
           'max_select', m.max_select, 'is_required', m.is_required,
           'allow_quantity', m.allow_quantity, 'max_quantity', m.max_quantity,
           'display_order', m.display_order, 'is_active', m.is_active)
           order by m.display_order, m.name), '[]'::jsonb)
    into v_modifiers
    from public.modifiers m
    join public.menu_items i
      on i.organization_id = m.organization_id and i.id = m.menu_item_id
     and i.restaurant_id = p_restaurant_id
     and i.deleted_at is null
     and (p_branch_id is null or i.branch_id is null or i.branch_id = p_branch_id)
    where m.organization_id = p_organization_id
      and m.restaurant_id   = p_restaurant_id
      and m.deleted_at is null
      and (p_branch_id is null or m.branch_id is null or m.branch_id = p_branch_id);

  -- modifier options: children of the RETURNED modifier set (which itself
  -- requires the parent item in the set) — tombstone-filtered at each level.
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', mo.id, 'organization_id', mo.organization_id, 'restaurant_id', mo.restaurant_id,
           'branch_id', mo.branch_id, 'modifier_id', mo.modifier_id, 'name', mo.name,
           'price_delta_minor', mo.price_delta_minor,
           'display_order', mo.display_order, 'is_active', mo.is_active, 'kitchen_meat', mo.kitchen_meat)
           order by mo.display_order, mo.name), '[]'::jsonb)
    into v_options
    from public.modifier_options mo
    join public.modifiers m
      on m.organization_id = mo.organization_id and m.id = mo.modifier_id
     and m.restaurant_id = p_restaurant_id
     and m.deleted_at is null
     and (p_branch_id is null or m.branch_id is null or m.branch_id = p_branch_id)
    join public.menu_items i
      on i.organization_id = m.organization_id and i.id = m.menu_item_id
     and i.restaurant_id = p_restaurant_id
     and i.deleted_at is null
     and (p_branch_id is null or i.branch_id is null or i.branch_id = p_branch_id)
    where mo.organization_id = p_organization_id
      and mo.restaurant_id   = p_restaurant_id
      and mo.deleted_at is null
      and (p_branch_id is null or mo.branch_id is null or mo.branch_id = p_branch_id);

  return jsonb_build_object(
    'ok', true,
    'entity', 'menu',
    'currency_code', v_currency,
    'categories', v_categories,
    'items', v_items,
    'sizes', v_sizes,
    'variants', v_variants,
    'modifiers', v_modifiers,
    'modifier_options', v_options,
    'server_ts', now());
end;
$function$;

-- ---- sales_summary (rank gate) -----------------------------------------------
CREATE OR REPLACE FUNCTION app.sales_summary(p_organization_id uuid, p_restaurant_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor    uuid := app.current_app_user_id();
  v_rank     integer;
  v_currency text;
  v_agg      jsonb;
begin
  if v_actor is null then
    raise exception 'sales_summary: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'sales_summary: organization_id is required' using errcode = '42501';
  end if;

  -- authority over the PASSED scope (downward-only coverage); 0 => not a covering member.
  v_rank := app.actor_read_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'sales_summary: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then  -- cashier/kitchen_staff/accountant cannot read the summary
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'sales_summary');
  end if;

  select o.default_currency into v_currency
    from public.organizations o
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'sales_summary: organization not found (or deleted)' using errcode = '42501';
  end if;

  with days as (
    -- 6 prior days + today, ascending (zero-filled below).
    select generate_series(current_date - 6, current_date, interval '1 day')::date as day
  ),
  scoped_orders as (
    select o.created_at::date as day,
           count(*)::bigint   as orders_count
    from public.orders o
    join public.branches b
      on b.organization_id = o.organization_id
     and b.restaurant_id   = o.restaurant_id
     and b.id              = o.branch_id
     and b.deleted_at is null
    join public.restaurants r
      on r.organization_id = o.organization_id
     and r.id              = o.restaurant_id
     and r.deleted_at is null
    where o.organization_id = p_organization_id
      and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or o.branch_id     = p_branch_id)
      and o.deleted_at is null
      and o.status not in ('cancelled', 'voided')
      and o.created_at::date between current_date - 6 and current_date
    group by o.created_at::date
  ),
  scoped_payments as (
    select p.created_at::date                       as day,
           count(*)::bigint                         as payments_count,
           coalesce(sum(p.amount_minor), 0)::bigint as gross_minor   -- SUM(bigint) is numeric; cast back (D-007)
    from public.payments p
    join public.orders o
      on o.organization_id = p.organization_id
     and o.id              = p.order_id
     and o.deleted_at is null
     and o.status not in ('cancelled', 'voided')  -- defensive belt; RF-062 blocks this structurally
    join public.branches b
      on b.organization_id = p.organization_id
     and b.restaurant_id   = p.restaurant_id
     and b.id              = p.branch_id
     and b.deleted_at is null
    join public.restaurants r
      on r.organization_id = p.organization_id
     and r.id              = p.restaurant_id
     and r.deleted_at is null
    where p.organization_id = p_organization_id
      and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or p.branch_id     = p_branch_id)
      and p.deleted_at is null
      and p.status = 'completed'                    -- only completed payments are money taken (RF-075)
      and p.created_at::date between current_date - 6 and current_date
    group by p.created_at::date
  )
  select jsonb_build_object(
    'today', jsonb_build_object(
      'orders_count',   coalesce((select so.orders_count   from scoped_orders   so where so.day = current_date), 0),
      'payments_count', coalesce((select sp.payments_count from scoped_payments sp where sp.day = current_date), 0),
      'gross_minor',    coalesce((select sp.gross_minor    from scoped_payments sp where sp.day = current_date), 0)),
    'last_7_days', (
      select jsonb_agg(jsonb_build_object(
               'day',          d.day,
               'orders_count', coalesce(so.orders_count, 0),
               'gross_minor',  coalesce(sp.gross_minor, 0)) order by d.day)
      from days d
      left join scoped_orders   so on so.day = d.day
      left join scoped_payments sp on sp.day = d.day))
  into v_agg;

  return jsonb_build_object('ok', true, 'entity', 'sales_summary', 'currency_code', v_currency) || v_agg;
end;
$function$;

-- ---- list_printers (rank gate) -----------------------------------------------
CREATE OR REPLACE FUNCTION app.list_printers(p_organization_id uuid, p_restaurant_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor    uuid := app.current_app_user_id();
  v_rank     integer;
  v_printers jsonb;
  v_routes   jsonb;
  v_stations jsonb;
begin
  if v_actor is null then
    raise exception 'list_printers: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'list_printers: organization_id is required' using errcode = '42501';
  end if;

  -- authority over the PASSED scope (downward-only coverage); 0 => not a covering member.
  v_rank := app.actor_read_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'list_printers: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then  -- cashier/kitchen_staff/accountant cannot manage printers
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'printer_device');
  end if;

  -- printers: tombstone-filtered + LIVE branch/restaurant only; ordered by display_name.
  select coalesce(jsonb_agg(item order by (item ->> 'display_name'), (item ->> 'id')), '[]'::jsonb)
    into v_printers
  from (
    select jsonb_build_object(
      'id',                pd.id,
      'display_name',      pd.display_name,
      'connection_type',   pd.connection_type,
      'role',              pd.role,
      'paper_width',       pd.paper_width,
      'connection_config', pd.connection_config,
      'is_enabled',        pd.is_enabled,
      'revision',          pd.revision,
      'created_at',        pd.created_at,
      'updated_at',        pd.updated_at
    ) as item
    from public.printer_devices pd
    join public.branches b
      on b.organization_id = pd.organization_id
     and b.restaurant_id   = pd.restaurant_id
     and b.id              = pd.branch_id
     and b.deleted_at is null
    join public.restaurants r
      on r.organization_id = pd.organization_id
     and r.id              = pd.restaurant_id
     and r.deleted_at is null
    where pd.organization_id = p_organization_id
      and (p_restaurant_id is null or pd.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or pd.branch_id     = p_branch_id)
      and pd.deleted_at is null
  ) t;

  -- routes: the station -> printer map (spec §6); tombstone-filtered + LIVE
  -- branch/restaurant only (soft_delete_printer_device already tombstones a
  -- removed printer's routes, so no extra printer-liveness filter is needed).
  select coalesce(jsonb_agg(item order by (item ->> 'id')), '[]'::jsonb)
    into v_routes
  from (
    select jsonb_build_object(
      'id',                pr.id,
      'station_id',        pr.station_id,
      'printer_device_id', pr.printer_device_id,
      'is_enabled',        pr.is_enabled
    ) as item
    from public.printer_routes pr
    join public.branches b
      on b.organization_id = pr.organization_id
     and b.restaurant_id   = pr.restaurant_id
     and b.id              = pr.branch_id
     and b.deleted_at is null
    join public.restaurants r
      on r.organization_id = pr.organization_id
     and r.id              = pr.restaurant_id
     and r.deleted_at is null
    where pr.organization_id = p_organization_id
      and (p_restaurant_id is null or pr.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or pr.branch_id     = p_branch_id)
      and pr.deleted_at is null
  ) t;

  -- stations: LIVE only (is_active + not tombstoned) on a LIVE branch/restaurant,
  -- so the dashboard can offer valid routing targets; ordered by name.
  select coalesce(jsonb_agg(item order by (item ->> 'name'), (item ->> 'id')), '[]'::jsonb)
    into v_stations
  from (
    select jsonb_build_object('id', s.id, 'name', s.name) as item
    from public.stations s
    join public.branches b
      on b.organization_id = s.organization_id
     and b.restaurant_id   = s.restaurant_id
     and b.id              = s.branch_id
     and b.deleted_at is null
    join public.restaurants r
      on r.organization_id = s.organization_id
     and r.id              = s.restaurant_id
     and r.deleted_at is null
    where s.organization_id = p_organization_id
      and (p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or s.branch_id     = p_branch_id)
      and s.is_active
      and s.deleted_at is null
  ) t;

  return jsonb_build_object('ok', true, 'entity', 'printer_device',
    'printers', v_printers, 'routes', v_routes, 'stations', v_stations);
end;
$function$;

-- ---- list_tables (rank gate) -------------------------------------------------
CREATE OR REPLACE FUNCTION app.list_tables(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := app.current_app_user_id();
  v_rank  integer;
  v_items jsonb;
  v_sections jsonb;
  v_elements jsonb;
begin
  if v_actor is null then
    raise exception 'list_tables: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null then
    raise exception 'list_tables: organization_id and restaurant_id are required' using errcode = '42501';
  end if;

  v_rank := app.actor_read_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'list_tables: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'table');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'id', t.id, 'label', t.label, 'seats', t.seats, 'area', t.area,
           'status', t.status, 'is_active', t.is_active, 'branch_id', t.branch_id,
           'active_order_count', coalesce(oc.n, 0),
           'effective_state', app.table_effective_state(t.status, coalesce(oc.n, 0)),
           'group_id', gm.group_id,
           'section_id', t.section_id,
           'section_name', s.name,
           'section_display_order', s.display_order,
           'layout_x', t.layout_x,
           'layout_y', t.layout_y,
           -- 118: presentation-only shape key (NULL = classic).
           'visual_preset', t.visual_preset,
           -- 120: presentation-only material key (NULL = Auto).
           'visual_material', t.visual_material)
           order by t.label, t.id), '[]'::jsonb)
    into v_items
    from public.tables t
    left join public.table_group_members gm
      on gm.organization_id = t.organization_id and gm.table_id = t.id
    left join public.table_sections s
      on s.id = t.section_id and s.organization_id = t.organization_id
     and s.deleted_at is null
    left join (
      select o.branch_id, o.table_id, count(*)::int as n
        from public.orders o
        where o.organization_id = p_organization_id
          and (p_branch_id is null or o.branch_id = p_branch_id)
          -- REVIEW CORRECTION (B1): dine-in only — see pos_tables.
          and o.order_type      = 'dine_in'
          and o.table_id is not null
          and o.deleted_at is null
          and o.status in ('submitted', 'accepted', 'preparing', 'ready', 'served')
        group by o.branch_id, o.table_id
    ) oc on oc.table_id = t.id and oc.branch_id = t.branch_id
    where t.organization_id = p_organization_id
      and t.restaurant_id   = p_restaurant_id
      and (p_branch_id is null or t.branch_id = p_branch_id)
      and t.deleted_at is null;

  -- TABLE-FLOOR-LAYOUT-021: the SECTION CATALOG rides along for the dashboard
  -- (empty sections must render as empty canvases; a per-row join cannot list
  -- them). 118: + floor_preset. 121: + room_frame_preset (NULL = Standard).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', s.id, 'name', s.name, 'display_order', s.display_order,
           'is_active', s.is_active, 'branch_id', s.branch_id,
           'floor_preset', s.floor_preset,
           'room_frame_preset', s.room_frame_preset)
           order by s.display_order, s.name, s.id), '[]'::jsonb)
    into v_sections
    from public.table_sections s
    where s.organization_id = p_organization_id
      and s.restaurant_id   = p_restaurant_id
      and (p_branch_id is null or s.branch_id = p_branch_id)
      and s.deleted_at is null;

  -- TABLE-FLOOR-MAP-POLISH-027: the FIXTURE CATALOG rides along the same way
  -- (visual-only; the dashboard editor draws + edits them per section).
  -- 120: + visual_style (NULL = the kind's default artwork).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', e.id, 'section_id', e.section_id, 'kind', e.kind,
           'layout_x', e.layout_x, 'layout_y', e.layout_y,
           'width_norm', e.width_norm, 'height_norm', e.height_norm,
           'orientation_quarter_turns', e.orientation_quarter_turns,
           'label', e.label,
           'visual_style', e.visual_style)
           order by e.created_at, e.id), '[]'::jsonb)
    into v_elements
    from public.table_floor_elements e
    join public.table_sections s
      on s.id = e.section_id and s.organization_id = e.organization_id
     and s.deleted_at is null
    where e.organization_id = p_organization_id
      and e.restaurant_id   = p_restaurant_id
      and (p_branch_id is null or e.branch_id = p_branch_id)
      and e.deleted_at is null;

  return jsonb_build_object('ok', true, 'entity', 'table', 'tables', v_items,
                            'sections', v_sections, 'floor_elements', v_elements);
end;
$function$;

-- ---- list_quick_note_presets (rank gate) -------------------------------------
CREATE OR REPLACE FUNCTION app.list_quick_note_presets(p_organization_id uuid, p_restaurant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor   uuid := app.current_app_user_id();
  v_rank    integer;
  v_presets jsonb;
begin
  if v_actor is null then
    raise exception 'list_quick_note_presets: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null then
    raise exception 'list_quick_note_presets: organization_id and restaurant_id are required' using errcode = '42501';
  end if;

  v_rank := app.actor_read_rank_in_scope(p_organization_id, p_restaurant_id, null);
  if v_rank = 0 then
    raise exception 'list_quick_note_presets: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'quick_note_preset');
  end if;

  select coalesce(jsonb_agg(
           jsonb_build_object('id', q.id, 'label', q.label,
                              'display_order', q.display_order, 'is_active', q.is_active)
           order by q.display_order, q.label), '[]'::jsonb)
    into v_presets
    from public.quick_note_presets q
    where q.organization_id = p_organization_id
      and q.restaurant_id   = p_restaurant_id
      and q.deleted_at is null;

  return jsonb_build_object('ok', true, 'entity', 'quick_note_preset',
                            'presets', v_presets);
end;
$function$;

-- ---- get_branch_kitchen_workflow_mode (rank gate) ----------------------------
CREATE OR REPLACE FUNCTION app.get_branch_kitchen_workflow_mode(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := app.current_app_user_id();
  v_rank  integer;
  v_mode  text;
begin
  if v_actor is null then
    raise exception 'get_branch_kitchen_workflow_mode: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  v_rank := app.actor_read_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    -- no membership covering this scope (incl. cross-tenant): reveal nothing.
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  select b.kitchen_workflow_mode into v_mode
    from public.branches b
    where b.id = p_branch_id and b.organization_id = p_organization_id
      and b.restaurant_id = p_restaurant_id and b.deleted_at is null;
  if v_mode is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  return jsonb_build_object('ok', true, 'entity', 'branch', 'branch_id', p_branch_id,
                            'kitchen_workflow_mode', v_mode);
end;
$function$;

-- ---- get_branch_pos_shift_close_enabled (rank gate) --------------------------
CREATE OR REPLACE FUNCTION app.get_branch_pos_shift_close_enabled(p_organization_id uuid, p_restaurant_id uuid, p_branch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor   uuid := app.current_app_user_id();
  v_rank    integer;
  v_enabled boolean;
begin
  if v_actor is null then
    raise exception 'get_branch_pos_shift_close_enabled: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null or p_branch_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  v_rank := app.actor_read_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    -- no membership covering this scope (incl. cross-tenant): reveal nothing.
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  select b.pos_shift_close_enabled into v_enabled
    from public.branches b
    where b.id = p_branch_id and b.organization_id = p_organization_id
      and b.restaurant_id = p_restaurant_id and b.deleted_at is null;
  if v_enabled is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'branch');
  end if;
  return jsonb_build_object('ok', true, 'entity', 'branch', 'branch_id', p_branch_id,
                            'pos_shift_close_enabled', v_enabled);
end;
$function$;

-- ---- list_devices (rank gate) ------------------------------------------------
CREATE OR REPLACE FUNCTION app.list_devices(p_organization_id uuid, p_restaurant_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor uuid := app.current_app_user_id();
  v_rank  integer;
  v_items jsonb;
begin
  if v_actor is null then
    raise exception 'list_devices: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'list_devices: organization_id is required' using errcode = '42501';
  end if;

  -- authority over the PASSED scope (downward-only coverage); 0 => not a covering member.
  v_rank := app.actor_read_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'list_devices: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  if v_rank < 2 then     -- cashier/kitchen_staff/accountant cannot manage/list devices
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'device');
  end if;

  select coalesce(jsonb_agg(item order by (item ->> 'label'), (item ->> 'device_id')), '[]'::jsonb)
    into v_items
  from (
    select jsonb_build_object(
      'device_id',         d.id,
      'label',             d.label,
      'device_type',       d.device_type,
      'branch_id',         d.branch_id,
      'branch_label',      b.name,
      'status',            coalesce(lp.status, 'none'),
      'device_pairing_id', lp.id,
      'has_open_session',  exists (
        select 1 from public.device_sessions ds
        where ds.device_id = d.id and ds.revoked_at is null
      )
    ) as item
    from public.devices d
    join public.branches b on b.id = d.branch_id
    left join lateral (
      select p.id, p.status
      from public.device_pairings p
      where p.device_id = d.id and p.deleted_at is null
      order by p.created_at desc
      limit 1
    ) lp on true
    where d.organization_id = p_organization_id
      and (p_restaurant_id is null or d.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or d.branch_id     = p_branch_id)
      and d.deleted_at is null
  ) t;

  return jsonb_build_object('ok', true, 'entity', 'device', 'devices', v_items);
end;
$function$;

-- ---- owner_daily_report (rank + financial-read allowlist) ------------------------------------------
CREATE OR REPLACE FUNCTION app.owner_daily_report(p_organization_id uuid, p_restaurant_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor    uuid    := app.current_app_user_id();
  v_rank     integer;
  v_currency text;
  v_today    date    := current_date;
  v_prior    date    := current_date - 1;
  v_result   jsonb;
begin
  if v_actor is null then
    raise exception 'owner_daily_report: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_daily_report: organization_id is required' using errcode = '42501';
  end if;

  -- authority over the PASSED scope (downward-only coverage); 0 => not a covering member.
  v_rank := app.actor_read_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_daily_report: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  -- FINANCIAL-READ allowlist (GUC-free, app.can_read_financials-STYLE): the caller
  -- must hold an ACTIVE membership covering the PASSED scope (downward-only,
  -- mirroring app.actor_rank_in_scope) whose role is a financial-read role —
  -- cashier / manager / restaurant_owner / org_owner / accountant; kitchen_staff
  -- is DENIED.
  -- ADMIN-126B: ...or a live, scoped, read-only platform support session. The
  -- tenant allowlist below is untouched; this only adds a second way in for an
  -- actor who holds no membership at all.
  if not app.platform_support_can_read_scope(p_organization_id, p_restaurant_id, p_branch_id)
     and not exists (
    select 1
    from public.memberships m
    where m.app_user_id     = v_actor
      and m.organization_id = p_organization_id
      and m.status          = 'active'
      and m.deleted_at is null
      and m.role in ('cashier', 'manager', 'restaurant_owner', 'org_owner', 'accountant')
      and (m.restaurant_id is null or m.restaurant_id = p_restaurant_id)
      and (m.branch_id     is null or m.branch_id     = p_branch_id)
  ) then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_daily_report');
  end if;

  -- OPS-043 Phase 5A: the EFFECTIVE currency, not the organization
  -- default. Phase 1 made restaurants.currency_override writable and
  -- Phase 2 moved owner_order_history / owner_active_orders onto the
  -- coalesce; this envelope was left behind, so a restaurant operating
  -- in an overridden currency had its Overview labelled with the org's.
  -- With different exponents that is not a wrong symbol but a wrong
  -- NUMBER: 47400 minor units reads JOD 47.400 under one label and
  -- 474.00 under the other, on the same screen.
  --
  -- An ORG-WIDE call (no restaurant in scope) keeps the org default:
  -- there is no single restaurant whose override could apply. A
  -- restaurant that is missing, deleted, or belongs to another
  -- organization falls back the same way, so the LEFT JOIN can never
  -- import a sibling tenant's currency.
  --
  -- The `not found` test still keys on the ORGANIZATION row, so a
  -- missing/deleted org raises exactly as before.
  select coalesce(r.currency_override, o.default_currency) into v_currency
    from public.organizations o
    left join public.restaurants r
      on r.id              = p_restaurant_id
     and r.organization_id = o.id
     and r.deleted_at is null
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'owner_daily_report: organization not found (or deleted)' using errcode = '42501';
  end if;

  with branch_tz as (
    -- branch-local zone (RF-075): COALESCE(branch, restaurant); tz-less excluded.
    select b.organization_id, b.restaurant_id, b.id as branch_id,
           coalesce(b.timezone, r.timezone) as zone
    from public.branches b
    join public.restaurants r
      on r.organization_id = b.organization_id
     and r.id              = b.restaurant_id
     and r.deleted_at is null
    where b.deleted_at is null
  ),
  order_day as (
    select o.id as order_id,
           o.status,
           o.subtotal_minor,
           o.discount_total_minor,
           o.grand_total_minor,
           (o.created_at at time zone t.zone)::date        as business_day,
           -- RF-REPORT-002: branch-local hour (0..23) for the sales-by-hour chart.
           extract(hour from (o.created_at at time zone t.zone))::int as business_hour
    from public.orders o
    join branch_tz t
      on t.organization_id = o.organization_id
     and t.branch_id       = o.branch_id
    where o.organization_id = p_organization_id
      and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or o.branch_id     = p_branch_id)
      and o.deleted_at is null
      and t.zone is not null
      and (o.created_at at time zone t.zone)::date in (v_today, v_prior)
  ),
  item_rollup as (
    -- per-order pre-discount gross + item-level discount (integer sums).
    select oi.order_id,
           sum(oi.line_total_minor + oi.line_discount_minor) as gross_minor,
           sum(oi.line_discount_minor)                       as item_discount_minor
    from public.order_items oi
    where oi.deleted_at is null
      and oi.status not in ('voided', 'cancelled')
      and oi.order_id in (select od.order_id from order_day od)
    group by oi.order_id
  ),
  payment_day as (
    -- completed payments joined to LIVE non-void/cancel orders, branch-local day.
    select p.id,
           p.method,
           p.amount_minor,
           p.created_at,
           (p.created_at at time zone t.zone)::date as business_day
    from public.payments p
    join branch_tz t
      on t.organization_id = p.organization_id
     and t.branch_id       = p.branch_id
    join public.orders o
      on o.organization_id = p.organization_id
     and o.id              = p.order_id
     and o.deleted_at is null
     and o.status not in ('cancelled', 'voided')  -- defensive belt (RF-062 blocks structurally)
    where p.organization_id = p_organization_id
      and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or p.branch_id     = p_branch_id)
      and p.deleted_at is null
      and p.status = 'completed'
      and t.zone is not null
      and (p.created_at at time zone t.zone)::date in (v_today, v_prior)
  ),
  -- MONEY-SETTLEMENT-CONSISTENCY-001 removed the `paid_orders` CTE. It was a MARKER
  -- ("a completed payment row exists"), and it was DAY-KEYED: it matched the PAYMENT's
  -- branch-local day against the ORDER's branch-local day, so an order billed at 23:50
  -- and paid at 00:10 was counted unpaid forever. Settlement is a property of the ORDER,
  -- not of a calendar day, so unpaid_count now asks the canonical predicate directly.
  sales as (
    -- billed sales = orders NOT voided/cancelled/draft.
    select od.business_day,
           count(*)::bigint                                                                as order_count,
           count(*) filter (where od.status = 'completed')::bigint                         as completed_count,
           -- OUTSTANDING money, the canonical rule. A NON-CHARGEABLE zero-total order owes
           -- nothing and is NOT counted; an UNDER-COVERED order still owes and IS counted.
           count(*) filter (
             where not app.order_is_fully_settled(p_organization_id, od.order_id)
           )::bigint                                                                        as unpaid_count,
           coalesce(sum(ir.gross_minor), 0)::bigint                                         as gross_minor,
           (coalesce(sum(ir.item_discount_minor), 0)
             + coalesce(sum(od.discount_total_minor), 0))::bigint                           as discount_minor,
           coalesce(sum(od.subtotal_minor - od.discount_total_minor), 0)::bigint            as net_minor
    from order_day od
    left join item_rollup ir on ir.order_id = od.order_id
    where od.status not in ('voided', 'cancelled', 'draft')
    group by od.business_day
  ),
  voids as (
    select od.business_day,
           count(*)::bigint                              as void_count,
           coalesce(sum(od.grand_total_minor), 0)::bigint as void_total_minor
    from order_day od
    where od.status = 'voided'
    group by od.business_day
  ),
  collected as (
    select business_day,
           coalesce(sum(amount_minor), 0)::bigint                              as collected_minor,
           coalesce(sum(amount_minor) filter (where method = 'cash'), 0)::bigint as cash_minor
    from payment_day
    group by business_day
  ),
  last_cash as (
    -- the most recent completed cash payment on the day (id desc tiebreak).
    select distinct on (business_day)
           business_day, amount_minor as last_cash_payment_minor
    from payment_day
    where method = 'cash'
    order by business_day, created_at desc, id desc
  ),
  tenders as (
    select business_day,
           jsonb_agg(jsonb_build_object('method', method, 'count', cnt, 'total_minor', total_minor)
                     order by method) as tenders
    from (
      select business_day, method,
             count(*)::bigint                       as cnt,
             coalesce(sum(amount_minor), 0)::bigint as total_minor
      from payment_day
      group by business_day, method
    ) g
    group by business_day
  ),
  hourly_net as (
    -- RF-REPORT-002: TODAY's BILLED net (subtotal - discount) per branch-local
    -- hour, over the SAME billed orders as `sales` (void/cancelled/draft excluded).
    select od.business_hour                                                     as hour,
           coalesce(sum(od.subtotal_minor - od.discount_total_minor), 0)::bigint as net_minor
    from order_day od
    where od.business_day = v_today
      and od.status not in ('voided', 'cancelled', 'draft')
    group by od.business_hour
  ),
  hourly_series as (
    -- 24 zero-filled buckets so the chart axis is stable (honest zeros).
    select h.hour::int                                                                        as hour,
           coalesce((select hn.net_minor from hourly_net hn where hn.hour = h.hour), 0)::bigint as net_minor
    from generate_series(0, 23) as h(hour)
  ),
  closed_shifts_today as (
    -- RF-REPORT-003: CLOSED (or reconciled) shifts whose BRANCH-LOCAL closed_at
    -- day is TODAY (tz-less branches excluded, same as the sales figures). Reads
    -- the RF-055-persisted expected/counted/variance (integer minor). A shift
    -- that spanned midnight is attributed to its CLOSE day (cash-count day).
    select s.id                    as shift_id,
           s.branch_id,
           b.name                  as branch_name,
           ep.display_name         as closed_by_name,
           -- BRANCH-LOCAL display strings (consistent with the closed_at bucketing;
           -- never leak a raw UTC ISO whose calendar date contradicts the bucket).
           to_char((s.opened_at at time zone t.zone), 'YYYY-MM-DD HH24:MI') as opened_at,
           to_char((s.closed_at at time zone t.zone), 'YYYY-MM-DD HH24:MI') as closed_at,
           s.expected_total_minor,
           s.counted_total_minor,
           s.variance_minor
    from public.shifts s
    join branch_tz t
      on t.organization_id = s.organization_id
     and t.branch_id       = s.branch_id
    join public.branches b
      on b.organization_id = s.organization_id
     and b.id              = s.branch_id
    left join public.employee_profiles ep
      on ep.organization_id = s.organization_id
     and ep.id             = s.closed_by_employee_profile_id
    where s.organization_id = p_organization_id
      and (p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or s.branch_id     = p_branch_id)
      and s.deleted_at is null
      and s.status in ('closed', 'reconciled')
      and s.closed_at is not null
      and t.zone is not null
      and (s.closed_at at time zone t.zone)::date = v_today
  ),
  open_shifts as (
    -- OPEN shifts NOW in scope (point-in-time count; NOT day/tz bucketed).
    select count(*)::bigint as cnt
    from public.shifts s
    where s.organization_id = p_organization_id
      and (p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or s.branch_id     = p_branch_id)
      and s.deleted_at is null
      and s.status in ('opening', 'open', 'closing')
  )
  select jsonb_build_object(
    'today', jsonb_build_object(
      'order_count',             coalesce((select s.order_count     from sales s     where s.business_day = v_today), 0),
      'completed_count',         coalesce((select s.completed_count from sales s     where s.business_day = v_today), 0),
      'open_count',              coalesce((select s.order_count - s.completed_count from sales s where s.business_day = v_today), 0),
      'unpaid_count',            coalesce((select s.unpaid_count    from sales s     where s.business_day = v_today), 0),
      'gross_minor',             coalesce((select s.gross_minor     from sales s     where s.business_day = v_today), 0),
      'discount_minor',          coalesce((select s.discount_minor  from sales s     where s.business_day = v_today), 0),
      'net_minor',               coalesce((select s.net_minor       from sales s     where s.business_day = v_today), 0),
      'void_count',              coalesce((select v.void_count      from voids v     where v.business_day = v_today), 0),
      'void_total_minor',        coalesce((select v.void_total_minor from voids v    where v.business_day = v_today), 0),
      'collected_minor',         coalesce((select c.collected_minor from collected c where c.business_day = v_today), 0),
      'cash_minor',              coalesce((select c.cash_minor      from collected c where c.business_day = v_today), 0),
      'last_cash_payment_minor', coalesce((select l.last_cash_payment_minor from last_cash l where l.business_day = v_today), 0),
      'tenders',                 coalesce((select t.tenders         from tenders t   where t.business_day = v_today), '[]'::jsonb)),
    'prior_day', jsonb_build_object(
      'order_count',  coalesce((select s.order_count from sales s     where s.business_day = v_prior), 0),
      'gross_minor',  coalesce((select s.gross_minor from sales s     where s.business_day = v_prior), 0),
      'net_minor',    coalesce((select s.net_minor   from sales s     where s.business_day = v_prior), 0),
      'cash_minor',   coalesce((select c.cash_minor  from collected c where c.business_day = v_prior), 0)),
    -- RF-REPORT-002: TODAY's 24 sales-by-hour buckets (billed net, integer minor).
    'hourly', coalesce(
      (select jsonb_agg(jsonb_build_object('hour', hs.hour, 'net_minor', hs.net_minor) order by hs.hour)
       from hourly_series hs),
      '[]'::jsonb),
    -- RF-REPORT-003: TODAY's shift / cash reconciliation (stored RF-055 values).
    'shift_cash', jsonb_build_object(
      'closed_shift_count',  coalesce((select count(*)::int from closed_shifts_today), 0),
      'open_shift_count',    coalesce((select cnt::int from open_shifts), 0),
      'expected_cash_minor', coalesce((select sum(expected_total_minor)::bigint from closed_shifts_today), 0),
      'counted_cash_minor',  coalesce((select sum(counted_total_minor)::bigint  from closed_shifts_today), 0),
      'cash_variance_minor', coalesce((select sum(variance_minor)::bigint       from closed_shifts_today), 0),
      'last_closed_shift', (
        select jsonb_build_object(
                 'shift_id',            cs.shift_id,
                 'branch_id',           cs.branch_id,
                 'branch_name',         cs.branch_name,
                 'opened_at',           cs.opened_at,
                 'closed_at',           cs.closed_at,
                 'closed_by_name',      cs.closed_by_name,
                 'expected_cash_minor', cs.expected_total_minor,
                 'counted_cash_minor',  cs.counted_total_minor,
                 'cash_variance_minor', cs.variance_minor)
        from closed_shifts_today cs
        order by cs.closed_at desc, cs.shift_id desc
        limit 1),
      'recent_closed_shifts', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'shift_id',            r.shift_id,
                 'branch_id',           r.branch_id,
                 'branch_name',         r.branch_name,
                 'closed_at',           r.closed_at,
                 'closed_by_name',      r.closed_by_name,
                 'expected_cash_minor', r.expected_total_minor,
                 'counted_cash_minor',  r.counted_total_minor,
                 'cash_variance_minor', r.variance_minor)
               order by r.closed_at desc, r.shift_id desc)
        from (select * from closed_shifts_today order by closed_at desc, shift_id desc limit 5) r),
        '[]'::jsonb))
  ) into v_result;

  return jsonb_build_object(
    'ok', true,
    'entity', 'owner_daily_report',
    'currency_code', v_currency,
    'business_date', v_today
  ) || v_result;
end;
$function$;

-- ---- owner_sales_series (rank + financial-read allowlist) ------------------------------------------
CREATE OR REPLACE FUNCTION app.owner_sales_series(p_organization_id uuid, p_restaurant_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid, p_range text DEFAULT 'today'::text, p_start date DEFAULT NULL::date, p_end date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor    uuid := app.current_app_user_id();
  v_rank     integer;
  v_currency text;
  v_span     integer;  -- window length in days, for the predefined ranges
  v_end_off  integer;  -- days back from a branch's local_today to the window end
  v_custom   boolean := false;
  v_buckets  jsonb;
begin
  if v_actor is null then
    raise exception 'owner_sales_series: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_sales_series: organization_id is required' using errcode = '42501';
  end if;

  -- ---------------------------------------------------------------------
  -- Window selection. A CUSTOM window is requested by supplying BOTH bounds;
  -- supplying exactly one is a malformed request rather than a silent
  -- half-open range, because "from the 3rd" has no defensible end and would
  -- quietly become an unbounded historical scan.
  -- ---------------------------------------------------------------------
  if p_start is not null or p_end is not null then
    if p_start is null or p_end is null then
      raise exception 'owner_sales_series: p_start and p_end must be supplied together'
        using errcode = '22023';
    end if;
    if p_end < p_start then
      raise exception 'owner_sales_series: p_end precedes p_start'
        using errcode = '22023';
    end if;
    -- INCLUSIVE of both endpoints, so a single day is start = end and spans 1
    -- day. 92 days is therefore (end - start) <= 91: a full calendar quarter
    -- is expressible, and anything larger is refused rather than scanned.
    if (p_end - p_start) > 91 then
      raise exception 'owner_sales_series: window exceeds 92 days'
        using errcode = '22023';
    end if;
    v_custom := true;
  else
    -- Same range vocabulary and the same (span, end_offset) mapping as
    -- app.owner_report_range, so a chart and a KPI card cannot describe
    -- different windows while claiming the same label.
    case p_range
      when 'today'     then v_span := 1;  v_end_off := 0;
      when 'yesterday' then v_span := 1;  v_end_off := 1;
      when 'last7'     then v_span := 7;  v_end_off := 0;
      when 'last30'    then v_span := 30; v_end_off := 0;
      when 'last60'    then v_span := 60; v_end_off := 0;
      when 'last90'    then v_span := 90; v_end_off := 0;
      else raise exception 'owner_sales_series: unknown range %', p_range using errcode = '22023';
    end case;
  end if;

  -- Authority over the PASSED scope (downward-only coverage). 0 => the caller
  -- holds no membership covering it.
  v_rank := app.actor_read_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_sales_series: caller has no active membership covering the requested scope'
      using errcode = '42501';
  end if;

  -- FINANCIAL-READ allowlist — GUC-FREE, and deliberately the same inline
  -- predicate app.owner_report_range uses rather than app.can_read_financials
  -- or app.current_org_id: those resolve through a GUC that is not set in the
  -- JWT path this family is called on, and would deny a legitimate owner.
  -- kitchen_staff is DENIED here, as everywhere in owner financial analytics.
  -- ADMIN-126B: ...or a live, scoped, read-only platform support session. The
  -- tenant allowlist below is untouched; this only adds a second way in for an
  -- actor who holds no membership at all.
  if not app.platform_support_can_read_scope(p_organization_id, p_restaurant_id, p_branch_id)
     and not exists (
    select 1
    from public.memberships m
    where m.app_user_id     = v_actor
      and m.organization_id = p_organization_id
      and m.status          = 'active'
      and m.deleted_at is null
      and m.role in ('cashier', 'manager', 'restaurant_owner', 'org_owner', 'accountant')
      and (m.restaurant_id is null or m.restaurant_id = p_restaurant_id)
      and (m.branch_id     is null or m.branch_id     = p_branch_id)
  ) then
    -- A soft denial object, matching the owner-report family: a raise here
    -- would leak scope existence through the error channel.
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_sales_series');
  end if;

  -- OPS-043 Phase 5A: the EFFECTIVE currency, not the organization
  -- default. Phase 1 made restaurants.currency_override writable and
  -- Phase 2 moved owner_order_history / owner_active_orders onto the
  -- coalesce; this envelope was left behind, so a restaurant operating
  -- in an overridden currency had its Overview labelled with the org's.
  -- With different exponents that is not a wrong symbol but a wrong
  -- NUMBER: 47400 minor units reads JOD 47.400 under one label and
  -- 474.00 under the other, on the same screen.
  --
  -- An ORG-WIDE call (no restaurant in scope) keeps the org default:
  -- there is no single restaurant whose override could apply. A
  -- restaurant that is missing, deleted, or belongs to another
  -- organization falls back the same way, so the LEFT JOIN can never
  -- import a sibling tenant's currency.
  --
  -- The `not found` test still keys on the ORGANIZATION row, so a
  -- missing/deleted org raises exactly as before.
  select coalesce(r.currency_override, o.default_currency) into v_currency
    from public.organizations o
    left join public.restaurants r
      on r.id              = p_restaurant_id
     and r.organization_id = o.id
     and r.deleted_at is null
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'owner_sales_series: organization not found (or deleted)' using errcode = '42501';
  end if;

  with branch_tz_base as (
    -- Branch-local zone (RF-075): COALESCE(branch, restaurant). A tz-less
    -- branch is EXCLUDED from financial windows, exactly as the owner-report
    -- family does — without a zone there is no defensible "day" to bucket into.
    --
    -- ORG-SCOPED AT THE SOURCE: SECURITY DEFINER bypasses RLS and the window
    -- CTE reads this directly, so without this filter an org-wide call would
    -- compute day boundaries from OTHER tenants' branches (D-001 / RISK R-003).
    select b.organization_id, b.restaurant_id, b.id as branch_id,
           coalesce(b.timezone, r.timezone) as zone
    from public.branches b
    join public.restaurants r
      on r.organization_id = b.organization_id
     and r.id              = b.restaurant_id
     and r.deleted_at is null
    where b.organization_id = p_organization_id
      and b.deleted_at is null
      and coalesce(b.timezone, r.timezone) is not null
  ),
  branch_tz as (
    -- PER-BRANCH window bounds, each in that branch's OWN zone. An org-wide
    -- call must never pick one organization-wide timezone first: two branches
    -- an hour apart genuinely close their day at different instants, and
    -- collapsing that would move revenue between days for one of them.
    select bt.organization_id, bt.restaurant_id, bt.branch_id, bt.zone,
           case when v_custom then p_start
                else (lt.local_today - v_end_off - (v_span - 1)) end as win_start,
           case when v_custom then p_end
                else (lt.local_today - v_end_off) end                as win_end
    from branch_tz_base bt
    cross join lateral (
      select (now() at time zone bt.zone)::date as local_today
    ) lt
  ),
  order_win as (
    -- Billed-candidate orders in scope, stamped with their BRANCH-LOCAL day.
    select o.id as order_id,
           o.status,
           o.order_type,
           o.subtotal_minor,
           o.discount_total_minor,
           o.grand_total_minor,
           (o.created_at at time zone t.zone)::date as business_day
    from public.orders o
    join branch_tz t
      on t.organization_id = o.organization_id
     and t.branch_id       = o.branch_id
    where o.organization_id = p_organization_id
      and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or o.branch_id     = p_branch_id)
      and o.deleted_at is null
      and (o.created_at at time zone t.zone)::date between t.win_start and t.win_end
  ),
  item_rollup as (
    -- S0.1 — LIVE LINES ONLY. A line voided or cancelled OFF a live bill was
    -- not sold, and the order writers already encode exactly that: after
    -- apply_discount or void_order, orders.subtotal_minor is recomputed as
    -- SUM(line_total_minor) over this same predicate.
    --
    -- Reading every non-deleted line instead let a struck-off line inflate
    -- gross_minor, and the discount captured on that dead line inflate
    -- discount_minor — while net_minor, which reads orders.subtotal_minor,
    -- stayed correct. That is precisely why it went unnoticed: the headline
    -- number was right and the number beside it was wrong.
    --
    -- The filter belongs on the CTE rather than on the gross sum alone, because
    -- gross and the item-discount component must describe the SAME set of
    -- lines. Otherwise the identity gross - discount = net stops holding.
    --
    -- NOTE this is only reachable for a dead line inside a LIVE order: when the
    -- ORDER itself is voided or cancelled, `sales` already drops it wholesale.
    select oi.order_id,
           sum(oi.line_total_minor + oi.line_discount_minor) as gross_minor,
           sum(oi.line_discount_minor)                       as item_discount_minor
    from public.order_items oi
    where oi.deleted_at is null
      and oi.status not in ('voided', 'cancelled')
      and oi.order_id in (select ow.order_id from order_win ow)
    group by oi.order_id
  ),
  payment_win as (
    -- COMPLETED payments only, on LIVE non-void/cancelled orders, stamped with
    -- the branch-local day of the PAYMENT. Collected is a cash-flow question,
    -- so it is bucketed by when money arrived, not when the order was raised.
    select p.method,
           p.amount_minor,
           (p.created_at at time zone t.zone)::date as business_day
    from public.payments p
    join branch_tz t
      on t.organization_id = p.organization_id
     and t.branch_id       = p.branch_id
    join public.orders o
      on o.organization_id = p.organization_id
     and o.id              = p.order_id
     and o.deleted_at is null
     and o.status not in ('cancelled', 'voided')
    where p.organization_id = p_organization_id
      and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or p.branch_id     = p_branch_id)
      and p.deleted_at is null
      and p.status = 'completed'
      and (p.created_at at time zone t.zone)::date between t.win_start and t.win_end
  ),
  billed_day as (
    select ow.business_day                                                      as day,
           count(*)::bigint                                                     as order_count,
           coalesce(sum(ir.gross_minor), 0)::bigint                             as gross_minor,
           (coalesce(sum(ir.item_discount_minor), 0)
             + coalesce(sum(ow.discount_total_minor), 0))::bigint               as discount_minor,
           coalesce(sum(ow.subtotal_minor - ow.discount_total_minor), 0)::bigint as net_minor
    from order_win ow
    left join item_rollup ir on ir.order_id = ow.order_id
    where ow.status not in ('voided', 'cancelled', 'draft')
    group by ow.business_day
  ),
  void_day as (
    select ow.business_day                                as day,
           count(*)::bigint                               as void_count,
           coalesce(sum(ow.grand_total_minor), 0)::bigint as void_total_minor
    from order_win ow
    where ow.status = 'voided'
    group by ow.business_day
  ),
  collected_day as (
    select pw.business_day                                                       as day,
           coalesce(sum(pw.amount_minor), 0)::bigint                             as collected_minor,
           coalesce(sum(pw.amount_minor) filter (where pw.method = 'cash'), 0)::bigint as cash_minor
    from payment_win pw
    group by pw.business_day
  ),
  method_day as (
    -- Element shape matches owner_report_range's `tenders`
    -- ({method, count, total_minor}) so a client can reuse one parser.
    select g.day,
           jsonb_agg(jsonb_build_object('method', g.method, 'count', g.cnt, 'total_minor', g.total_minor)
                     order by g.method) as by_method
    from (
      select pw.business_day                       as day,
             pw.method,
             count(*)::bigint                      as cnt,
             coalesce(sum(pw.amount_minor), 0)::bigint as total_minor
      from payment_win pw
      group by pw.business_day, pw.method
    ) g
    group by g.day
  ),
  type_day as (
    -- Only PERSISTED order_type values ('dine_in' / 'takeaway'); no invented
    -- grouping label ever enters this payload.
    select g.day,
           jsonb_agg(jsonb_build_object('order_type', g.order_type,
                                        'order_count', g.order_count,
                                        'net_minor', g.net_minor)
                     order by g.order_type) as by_order_type
    from (
      select ow.business_day as day,
             ow.order_type,
             count(*)::bigint as order_count,
             coalesce(sum(ow.subtotal_minor - ow.discount_total_minor), 0)::bigint as net_minor
      from order_win ow
      where ow.status not in ('voided', 'cancelled', 'draft')
      group by ow.business_day, ow.order_type
    ) g
    group by g.day
  ),
  all_days as (
    -- Every day that produced ANY fact: a day with only voids, or only a
    -- payment against an earlier order, is still a real day and must appear.
    select day from billed_day
    union select day from void_day
    union select day from collected_day
  )
  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'day',              to_char(d.day, 'YYYY-MM-DD'),
               'order_count',      coalesce(b.order_count, 0),
               'gross_minor',      coalesce(b.gross_minor, 0),
               'discount_minor',   coalesce(b.discount_minor, 0),
               'net_minor',        coalesce(b.net_minor, 0),
               'void_count',       coalesce(v.void_count, 0),
               'void_total_minor', coalesce(v.void_total_minor, 0),
               'collected_minor',  coalesce(c.collected_minor, 0),
               'cash_minor',       coalesce(c.cash_minor, 0),
               'by_method',        coalesce(m.by_method, '[]'::jsonb),
               'by_order_type',    coalesce(t.by_order_type, '[]'::jsonb)
             )
             order by d.day
           ),
           '[]'::jsonb
         )
    into v_buckets
    from all_days d
    left join billed_day    b on b.day = d.day
    left join void_day      v on v.day = d.day
    left join collected_day c on c.day = d.day
    left join method_day    m on m.day = d.day
    left join type_day      t on t.day = d.day;

  return jsonb_build_object(
    'ok',            true,
    'entity',        'owner_sales_series',
    'currency_code', v_currency,
    'range',         case when v_custom then 'custom' else p_range end,
    'buckets',       coalesce(v_buckets, '[]'::jsonb)
  );
end;
$function$;

-- ---- owner_top_items (rank + financial-read allowlist) ---------------------------------------------
CREATE OR REPLACE FUNCTION app.owner_top_items(p_organization_id uuid, p_restaurant_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid, p_range text DEFAULT 'today'::text, p_start date DEFAULT NULL::date, p_end date DEFAULT NULL::date, p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor    uuid := app.current_app_user_id();
  v_rank     integer;
  v_currency text;
  v_span     integer;  -- window length in days, for the preset ranges
  v_end_off  integer;  -- days back from a branch's local_today to the window end
  v_custom   boolean := false;
  -- Clamped, never rejected: a caller asking for 0 or 5000 rows has made a
  -- display choice, not a malformed request. Invalid WINDOWS raise; an
  -- out-of-band page size is simply bounded.
  v_limit    integer := least(greatest(coalesce(p_limit, 10), 1), 50);
  v_items    jsonb;
begin
  if v_actor is null then
    raise exception 'owner_top_items: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_top_items: organization_id is required' using errcode = '42501';
  end if;

  -- Window selection — the shared block (see the header).
  if p_start is not null or p_end is not null then
    if p_start is null or p_end is null then
      raise exception 'owner_top_items: p_start and p_end must be supplied together'
        using errcode = '22023';
    end if;
    if p_end < p_start then
      raise exception 'owner_top_items: p_end precedes p_start'
        using errcode = '22023';
    end if;
    if (p_end - p_start) > 91 then
      raise exception 'owner_top_items: window exceeds 92 days'
        using errcode = '22023';
    end if;
    v_custom := true;
  else
    case p_range
      when 'today'     then v_span := 1;  v_end_off := 0;
      when 'yesterday' then v_span := 1;  v_end_off := 1;
      when 'last7'     then v_span := 7;  v_end_off := 0;
      when 'last30'    then v_span := 30; v_end_off := 0;
      when 'last60'    then v_span := 60; v_end_off := 0;
      when 'last90'    then v_span := 90; v_end_off := 0;
      else raise exception 'owner_top_items: unknown range %', p_range using errcode = '22023';
    end case;
  end if;

  -- Authority over the PASSED scope (downward-only coverage). 0 => the caller
  -- holds no membership covering it.
  v_rank := app.actor_read_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_top_items: caller has no active membership covering the requested scope'
      using errcode = '42501';
  end if;

  -- FINANCIAL-READ allowlist — GUC-FREE, the same inline predicate the rest of
  -- the owner analytics family uses rather than app.can_read_financials /
  -- app.current_org_id, which resolve through a GUC that production's JWT path
  -- never sets and would deny a legitimate owner. kitchen_staff is DENIED.
  -- ADMIN-126B: ...or a live, scoped, read-only platform support session. The
  -- tenant allowlist below is untouched; this only adds a second way in for an
  -- actor who holds no membership at all.
  if not app.platform_support_can_read_scope(p_organization_id, p_restaurant_id, p_branch_id)
     and not exists (
    select 1
    from public.memberships m
    where m.app_user_id     = v_actor
      and m.organization_id = p_organization_id
      and m.status          = 'active'
      and m.deleted_at is null
      and m.role in ('cashier', 'manager', 'restaurant_owner', 'org_owner', 'accountant')
      and (m.restaurant_id is null or m.restaurant_id = p_restaurant_id)
      and (m.branch_id     is null or m.branch_id     = p_branch_id)
  ) then
    -- A soft denial object, matching the owner-report family: raising here
    -- would leak scope existence through the error channel.
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_top_items');
  end if;

  -- OPS-043 Phase 5A: the EFFECTIVE currency, not the organization
  -- default. Phase 1 made restaurants.currency_override writable and
  -- Phase 2 moved owner_order_history / owner_active_orders onto the
  -- coalesce; this envelope was left behind, so a restaurant operating
  -- in an overridden currency had its Overview labelled with the org's.
  -- With different exponents that is not a wrong symbol but a wrong
  -- NUMBER: 47400 minor units reads JOD 47.400 under one label and
  -- 474.00 under the other, on the same screen.
  --
  -- An ORG-WIDE call (no restaurant in scope) keeps the org default:
  -- there is no single restaurant whose override could apply. A
  -- restaurant that is missing, deleted, or belongs to another
  -- organization falls back the same way, so the LEFT JOIN can never
  -- import a sibling tenant's currency.
  --
  -- The `not found` test still keys on the ORGANIZATION row, so a
  -- missing/deleted org raises exactly as before.
  select coalesce(r.currency_override, o.default_currency) into v_currency
    from public.organizations o
    left join public.restaurants r
      on r.id              = p_restaurant_id
     and r.organization_id = o.id
     and r.deleted_at is null
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'owner_top_items: organization not found (or deleted)' using errcode = '42501';
  end if;

  with branch_tz_base as (
    -- Branch-local zone (RF-075): COALESCE(branch, restaurant); tz-less
    -- excluded. ORG-SCOPED AT THE SOURCE: SECURITY DEFINER bypasses RLS and the
    -- window CTE reads this directly, so without this filter an org-wide call
    -- would compute day boundaries from OTHER tenants' branches (D-001 / R-003).
    select b.organization_id, b.restaurant_id, b.id as branch_id,
           coalesce(b.timezone, r.timezone) as zone
    from public.branches b
    join public.restaurants r
      on r.organization_id = b.organization_id
     and r.id              = b.restaurant_id
     and r.deleted_at is null
    where b.organization_id = p_organization_id
      and b.deleted_at is null
      and coalesce(b.timezone, r.timezone) is not null
  ),
  branch_tz as (
    -- PER-BRANCH bounds for presets; the SAME fixed dates for every branch when
    -- the window is custom.
    select bt.organization_id, bt.restaurant_id, bt.branch_id, bt.zone,
           case when v_custom then p_start
                else (lt.local_today - v_end_off - (v_span - 1)) end as win_start,
           case when v_custom then p_end
                else (lt.local_today - v_end_off) end                as win_end
    from branch_tz_base bt
    cross join lateral (
      select (now() at time zone bt.zone)::date as local_today
    ) lt
  ),
  order_win as (
    -- BILLED orders in scope whose branch-local day falls in the window.
    select o.id as order_id
    from public.orders o
    join branch_tz t
      on t.organization_id = o.organization_id
     and t.branch_id       = o.branch_id
    where o.organization_id = p_organization_id
      and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or o.branch_id     = p_branch_id)
      and o.deleted_at is null
      and o.status not in ('voided', 'cancelled', 'draft')
      and (o.created_at at time zone t.zone)::date between t.win_start and t.win_end
  ),
  item_win as (
    -- LIVE lines of those orders. The status filter is the canonical one the
    -- order writers use when they recompute subtotal_minor, so a line voided
    -- off the bill stops counting towards its product's ranking.
    select oi.menu_item_id,
           oi.order_id,
           oi.quantity,
           oi.line_total_minor,
           oi.menu_item_name_snapshot,
           oi.created_at,
           oi.id
    from public.order_items oi
    join order_win ow on ow.order_id = oi.order_id
    where oi.organization_id = p_organization_id
      and oi.deleted_at is null
      and oi.status not in ('voided', 'cancelled')
  ),
  rollup as (
    select iw.menu_item_id,
           sum(iw.quantity)::bigint            as quantity,
           sum(iw.line_total_minor)::bigint    as revenue_minor,
           count(distinct iw.order_id)::bigint as order_count
    from item_win iw
    group by iw.menu_item_id
  ),
  display_name as (
    -- The most recently CAPTURED snapshot for this product, deterministically:
    -- newest line first, id as the final tie-break so two lines created in the
    -- same transaction still resolve to one answer.
    select distinct on (iw.menu_item_id)
           iw.menu_item_id,
           iw.menu_item_name_snapshot as name
    from item_win iw
    order by iw.menu_item_id, iw.created_at desc, iw.id desc
  ),
  ranked as (
    -- Revenue first (the question being asked), then quantity, then name, then
    -- the id — which is unique per group, so the order is TOTAL and two runs
    -- over identical data can never disagree about who is 9th and who is 10th.
    select r.menu_item_id, dn.name, r.quantity, r.revenue_minor, r.order_count
    from rollup r
    join display_name dn on dn.menu_item_id = r.menu_item_id
    order by r.revenue_minor desc, r.quantity desc, dn.name asc, r.menu_item_id asc
    limit v_limit
  )
  -- The aggregate repeats the ORDER BY: a LIMIT in a CTE selects WHICH rows
  -- survive, it does not promise the aggregate will consume them in that order.
  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'menu_item_id',  k.menu_item_id,
               'name',          k.name,
               'quantity',      k.quantity,
               'revenue_minor', k.revenue_minor,
               'order_count',   k.order_count
             )
             order by k.revenue_minor desc, k.quantity desc, k.name asc, k.menu_item_id asc
           ),
           '[]'::jsonb
         )
    into v_items
    from ranked k;

  return jsonb_build_object(
    'ok',            true,
    'entity',        'owner_top_items',
    'currency_code', v_currency,
    'range',         case when v_custom then 'custom' else p_range end,
    'limit',         v_limit,
    'items',         coalesce(v_items, '[]'::jsonb)
  );
end;
$function$;

-- ---- owner_report_currency_breakdown (rank + financial-read allowlist) -----------------------------
CREATE OR REPLACE FUNCTION app.owner_report_currency_breakdown(p_organization_id uuid, p_restaurant_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid, p_start date DEFAULT NULL::date, p_end date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor  uuid := app.current_app_user_id();
  v_rank   int;
  v_result jsonb;
begin
  if v_actor is null then
    raise exception 'owner_report_currency_breakdown: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_report_currency_breakdown: organization_id is required' using errcode = '42501';
  end if;
  if p_start is null or p_end is null or p_end < p_start then
    raise exception 'owner_report_currency_breakdown: a valid start/end date pair is required' using errcode = '42501';
  end if;

  v_rank := app.actor_read_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
  if v_rank = 0 then
    raise exception 'owner_report_currency_breakdown: caller has no active membership covering the requested scope' using errcode = '42501';
  end if;
  -- ADMIN-126B: ...or a live, scoped, read-only platform support session. The
  -- tenant allowlist below is untouched; this only adds a second way in for an
  -- actor who holds no membership at all.
  if not app.platform_support_can_read_scope(p_organization_id, p_restaurant_id, p_branch_id)
     and not exists (
    select 1
    from public.memberships m
    where m.app_user_id     = v_actor
      and m.organization_id = p_organization_id
      and m.status          = 'active'
      and m.deleted_at is null
      and m.role in ('cashier', 'manager', 'restaurant_owner', 'org_owner', 'accountant')
      and (m.restaurant_id is null or m.restaurant_id = p_restaurant_id)
      and (m.branch_id     is null or m.branch_id     = p_branch_id)
  ) then
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_report_currency_breakdown');
  end if;

  with branch_tz as (
    -- branch-local zone (RF-075): COALESCE(branch, restaurant); tz-less excluded.
    -- ORG-SCOPED at the source: SECURITY DEFINER bypasses RLS, so this filter is
    -- what keeps the CTE single-tenant (D-001 / RISK R-003).
    select b.organization_id, b.restaurant_id, b.id as branch_id,
           coalesce(b.timezone, r.timezone) as zone
    from public.branches b
    join public.restaurants r
      on r.organization_id = b.organization_id
     and r.id              = b.restaurant_id
     and r.deleted_at is null
    where b.organization_id = p_organization_id
      and b.deleted_at is null
      and coalesce(b.timezone, r.timezone) is not null
  ),
  order_win as (
    -- billed orders in the window: NOT voided / cancelled / draft, exactly the
    -- set `owner_report_range`'s `sales` CTE counts.
    select o.id as order_id,
           o.currency_code,
           o.status,
           o.subtotal_minor,
           o.discount_total_minor
    from public.orders o
    join branch_tz t
      on t.organization_id = o.organization_id
     and t.branch_id       = o.branch_id
    where o.organization_id = p_organization_id
      and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or o.branch_id     = p_branch_id)
      and o.deleted_at is null
      and o.status not in ('voided', 'cancelled', 'draft')
      and (o.created_at at time zone t.zone)::date between p_start and p_end
  ),
  item_rollup as (
    -- LIVE LINES ONLY, mirroring owner_report_range: a line struck off a live
    -- bill was not sold, so gross and the item-discount component must describe
    -- the same set of lines or the identity gross - discount = net breaks.
    select oi.order_id,
           sum(oi.line_total_minor + oi.line_discount_minor) as gross_minor,
           sum(oi.line_discount_minor)                       as item_discount_minor
    from public.order_items oi
    where oi.deleted_at is null
      and oi.status not in ('voided', 'cancelled')
      and oi.order_id in (select ow.order_id from order_win ow)
    group by oi.order_id
  ),
  order_cur as (
    select ow.currency_code,
           count(*)::bigint                                                      as order_count,
           count(*) filter (where ow.status = 'completed')::bigint               as completed_count,
           coalesce(sum(ir.gross_minor), 0)::bigint                              as gross_minor,
           (coalesce(sum(ir.item_discount_minor), 0)
             + coalesce(sum(ow.discount_total_minor), 0))::bigint                as discount_minor,
           coalesce(sum(ow.subtotal_minor - ow.discount_total_minor), 0)::bigint as net_minor
    from order_win ow
    left join item_rollup ir on ir.order_id = ow.order_id
    group by ow.currency_code
  ),
  pay_cur as (
    -- completed payments on live orders, grouped by the PAYMENT's own currency
    -- (a payment row carries its own code; it is not assumed to match the order).
    select p.currency_code,
           coalesce(sum(p.amount_minor), 0)::bigint                                          as collected_minor,
           coalesce(sum(p.amount_minor) filter (where p.method = 'cash'), 0)::bigint         as cash_minor
    from public.payments p
    join branch_tz t
      on t.organization_id = p.organization_id
     and t.branch_id       = p.branch_id
    join public.orders o
      on o.organization_id = p.organization_id
     and o.id              = p.order_id
     and o.deleted_at is null
     and o.status not in ('cancelled', 'voided')
    where p.organization_id = p_organization_id
      and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or p.branch_id     = p_branch_id)
      and p.deleted_at is null
      and p.status = 'completed'
      and (p.created_at at time zone t.zone)::date between p_start and p_end
    group by p.currency_code
  ),
  codes as (
    select currency_code from order_cur
    union
    select currency_code from pay_cur
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'currency_code',    c.currency_code,
           'order_count',      coalesce(oc.order_count, 0),
           'completed_count',  coalesce(oc.completed_count, 0),
           'gross_minor',      coalesce(oc.gross_minor, 0),
           'discount_minor',   coalesce(oc.discount_minor, 0),
           'net_minor',        coalesce(oc.net_minor, 0),
           'collected_minor',  coalesce(pc.collected_minor, 0),
           'cash_minor',       coalesce(pc.cash_minor, 0))
         order by c.currency_code), '[]'::jsonb)
    into v_result
  from codes c
  left join order_cur oc on oc.currency_code = c.currency_code
  left join pay_cur   pc on pc.currency_code = c.currency_code;

  return jsonb_build_object(
    'ok',           true,
    'entity',       'owner_report_currency_breakdown',
    'range_start',  to_char(p_start, 'YYYY-MM-DD'),
    'range_end',    to_char(p_end,   'YYYY-MM-DD'),
    'by_currency',  v_result
  );
end;
$function$;

-- ---- owner_report_range (rank + financial-read allowlist) ------------------------------------------
CREATE OR REPLACE FUNCTION app.owner_report_range(p_organization_id uuid, p_restaurant_id uuid DEFAULT NULL::uuid, p_branch_id uuid DEFAULT NULL::uuid, p_range text DEFAULT 'today'::text, p_start date DEFAULT NULL::date, p_end date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor      uuid    := app.current_app_user_id();
  v_rank       integer;
  v_currency   text;
  v_span       integer;  -- number of days in the window
  v_end_offset integer;  -- days back from a branch's local_today to cur_end
  v_custom     boolean := false;
  v_result     jsonb;
begin
  if v_actor is null then
    raise exception 'owner_report_range: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'owner_report_range: organization_id is required' using errcode = '42501';
  end if;

  -- Window selection — the shared block (see the header). A custom pair wins
  -- over p_range, exactly as in owner_sales_series.
  if p_start is not null or p_end is not null then
    if p_start is null or p_end is null then
      raise exception 'owner_report_range: p_start and p_end must be supplied together'
        using errcode = '22023';
    end if;
    if p_end < p_start then
      raise exception 'owner_report_range: p_end precedes p_start'
        using errcode = '22023';
    end if;
    if (p_end - p_start) > 91 then
      raise exception 'owner_report_range: window exceeds 92 days'
        using errcode = '22023';
    end if;
    v_custom := true;
    -- INCLUSIVE, so a single day is span 1. This drives both the prior-window
    -- length and the single-day hourly series.
    v_span   := (p_end - p_start) + 1;
  else
    -- Range -> (span, end_offset). Unknown range is a bad request, not a denial.
    case p_range
      when 'today'     then v_span := 1;  v_end_offset := 0;
      when 'yesterday' then v_span := 1;  v_end_offset := 1;
      when 'last7'     then v_span := 7;  v_end_offset := 0;
      when 'last30'    then v_span := 30; v_end_offset := 0;
      when 'last60'    then v_span := 60; v_end_offset := 0;
      when 'last90'    then v_span := 90; v_end_offset := 0;
      else raise exception 'owner_report_range: unknown range %', p_range using errcode = '22023';
    end case;
  end if;

  -- ==========================================================================
  -- ADMIN-126 — TWO CALLERS, ONE FORMULA.
  --
  -- The platform operations console reports each restaurant's sales for today.
  -- It reads them THROUGH THIS FUNCTION rather than computing its own, because
  -- a second revenue formula is a second source of truth: the day it disagrees
  -- with the owner's Dashboard, neither number can be trusted and there is no
  -- way to tell which is wrong. Everything below this gate is untouched and is
  -- evaluated identically for both callers — the body reads only scope and
  -- dates, never the caller.
  --
  -- The platform branch is NOT a membership, NOT an impersonation, and NOT a
  -- widening of tenant authority. It requires ALL of:
  --   * an active platform_admin_grants row  (app.is_platform_admin)
  --   * a VERIFIED aal2 session              (app.current_auth_assurance_level)
  --   * a transaction-local marker that only the audited SECURITY DEFINER
  --     platform read path sets.
  -- The marker is a defence-in-depth detail, not the boundary: PostgREST cannot
  -- set arbitrary GUCs, so it keeps a legitimate platform admin from reading
  -- tenant revenue OUTSIDE the reason-tagged, audited console path. The grant
  -- and aal2 are the actual gate, and no tenant caller can ever satisfy them.
  -- ==========================================================================
  if (coalesce(current_setting('app.platform_report_read', true), '') = 'on'
      and app.is_platform_admin()
      and app.current_auth_assurance_level() = 'aal2')
     -- ADMIN-126B: or a live, scoped, read-only support session, which is how
     -- the tenant Dashboard renders this same report during support.
     or app.platform_support_can_read_scope(p_organization_id, p_restaurant_id, p_branch_id) then
    null;  -- audited platform read: the tenant membership gate does not apply
  else
    -- authority over the PASSED scope (downward-only coverage); 0 => not a covering member.
    v_rank := app.actor_read_rank_in_scope(p_organization_id, p_restaurant_id, p_branch_id);
    if v_rank = 0 then
      raise exception 'owner_report_range: caller has no active membership covering the requested scope' using errcode = '42501';
    end if;
    -- FINANCIAL-READ allowlist (GUC-free, app.can_read_financials-STYLE): an ACTIVE
    -- membership covering the PASSED scope (downward-only) whose role is a financial-
    -- read role — cashier / manager / restaurant_owner / org_owner / accountant;
    -- kitchen_staff is DENIED.
    if not exists (
      select 1
      from public.memberships m
      where m.app_user_id     = v_actor
        and m.organization_id = p_organization_id
        and m.status          = 'active'
        and m.deleted_at is null
        and m.role in ('cashier', 'manager', 'restaurant_owner', 'org_owner', 'accountant')
        and (m.restaurant_id is null or m.restaurant_id = p_restaurant_id)
        and (m.branch_id     is null or m.branch_id     = p_branch_id)
    ) then
      return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'owner_report_range');
    end if;
  end if;

  -- OPS-043 Phase 5A: the EFFECTIVE currency, not the organization
  -- default. Phase 1 made restaurants.currency_override writable and
  -- Phase 2 moved owner_order_history / owner_active_orders onto the
  -- coalesce; this envelope was left behind, so a restaurant operating
  -- in an overridden currency had its Overview labelled with the org's.
  -- With different exponents that is not a wrong symbol but a wrong
  -- NUMBER: 47400 minor units reads JOD 47.400 under one label and
  -- 474.00 under the other, on the same screen.
  --
  -- An ORG-WIDE call (no restaurant in scope) keeps the org default:
  -- there is no single restaurant whose override could apply. A
  -- restaurant that is missing, deleted, or belongs to another
  -- organization falls back the same way, so the LEFT JOIN can never
  -- import a sibling tenant's currency.
  --
  -- The `not found` test still keys on the ORGANIZATION row, so a
  -- missing/deleted org raises exactly as before.
  select coalesce(r.currency_override, o.default_currency) into v_currency
    from public.organizations o
    left join public.restaurants r
      on r.id              = p_restaurant_id
     and r.organization_id = o.id
     and r.deleted_at is null
    where o.id = p_organization_id and o.deleted_at is null;
  if not found then
    raise exception 'owner_report_range: organization not found (or deleted)' using errcode = '42501';
  end if;

  with branch_tz_base as (
    -- branch-local zone (RF-075): COALESCE(branch, restaurant); tz-less excluded.
    -- ORG-SCOPED at the source (SECURITY DEFINER bypasses RLS): the `win` CTE
    -- reads branch_tz DIRECTLY (not via an org-filtered fact join), so without
    -- this filter an org-wide call's range_start/range_end would be computed over
    -- OTHER tenants' branches (D-001 / RISK R-003). All other consumers already
    -- re-scope via their fact tables; this keeps branch_tz itself single-tenant.
    select b.organization_id, b.restaurant_id, b.id as branch_id,
           coalesce(b.timezone, r.timezone) as zone
    from public.branches b
    join public.restaurants r
      on r.organization_id = b.organization_id
     and r.id              = b.restaurant_id
     and r.deleted_at is null
    where b.organization_id = p_organization_id
      and b.deleted_at is null
      and coalesce(b.timezone, r.timezone) is not null
  ),
  branch_tz as (
    -- per-branch local today + the current/prior window bounds. PRESETS are
    -- branch-local and relative; a CUSTOM pair is the same fixed calendar dates
    -- for every branch. The prior window is derived from cur_start in both
    -- cases, so it is always the immediately preceding equal-length window.
    select bt.organization_id, bt.restaurant_id, bt.branch_id, bt.zone,
           lt.local_today,
           w.cur_end,
           w.cur_start,
           (w.cur_start - 1)      as prev_end,
           (w.cur_start - v_span) as prev_start
    from branch_tz_base bt
    cross join lateral (
      select (now() at time zone bt.zone)::date as local_today
    ) lt
    cross join lateral (
      select case when v_custom then p_end
                  else (lt.local_today - v_end_offset) end                as cur_end,
             case when v_custom then p_start
                  else (lt.local_today - v_end_offset - (v_span - 1)) end as cur_start
    ) w
  ),
  order_win as (
    -- orders in scope, branch-local day + hour, tagged current ('cur') / prior.
    select o.id as order_id,
           o.status,
           o.subtotal_minor,
           o.discount_total_minor,
           o.grand_total_minor,
           (o.created_at at time zone t.zone)::date        as business_day,
           extract(hour from (o.created_at at time zone t.zone))::int as business_hour,
           case
             when (o.created_at at time zone t.zone)::date between t.cur_start  and t.cur_end  then 'cur'
             when (o.created_at at time zone t.zone)::date between t.prev_start and t.prev_end then 'prev'
           end as bucket
    from public.orders o
    join branch_tz t
      on t.organization_id = o.organization_id
     and t.branch_id       = o.branch_id
    where o.organization_id = p_organization_id
      and (p_restaurant_id is null or o.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or o.branch_id     = p_branch_id)
      and o.deleted_at is null
      and (o.created_at at time zone t.zone)::date between t.prev_start and t.cur_end
  ),
  item_rollup as (
    -- S0.1 — LIVE LINES ONLY. A line voided or cancelled OFF a live bill was
    -- not sold, and the order writers already encode exactly that: after
    -- apply_discount or void_order, orders.subtotal_minor is recomputed as
    -- SUM(line_total_minor) over this same predicate.
    --
    -- Reading every non-deleted line instead let a struck-off line inflate
    -- gross_minor, and the discount captured on that dead line inflate
    -- discount_minor — while net_minor, which reads orders.subtotal_minor,
    -- stayed correct. That is precisely why it went unnoticed: the headline
    -- number was right and the number beside it was wrong.
    --
    -- The filter belongs on the CTE rather than on the gross sum alone, because
    -- gross and the item-discount component must describe the SAME set of
    -- lines. Otherwise the identity gross - discount = net stops holding.
    --
    -- NOTE this is only reachable for a dead line inside a LIVE order: when the
    -- ORDER itself is voided or cancelled, `sales` already drops it wholesale.
    select oi.order_id,
           sum(oi.line_total_minor + oi.line_discount_minor) as gross_minor,
           sum(oi.line_discount_minor)                       as item_discount_minor
    from public.order_items oi
    where oi.deleted_at is null
      and oi.status not in ('voided', 'cancelled')
      and oi.order_id in (select ow.order_id from order_win ow)
    group by oi.order_id
  ),
  payment_win as (
    -- completed payments joined to LIVE non-void/cancel orders, tagged cur/prev.
    select p.id,
           p.method,
           p.amount_minor,
           p.created_at,
           case
             when (p.created_at at time zone t.zone)::date between t.cur_start  and t.cur_end  then 'cur'
             when (p.created_at at time zone t.zone)::date between t.prev_start and t.prev_end then 'prev'
           end as bucket
    from public.payments p
    join branch_tz t
      on t.organization_id = p.organization_id
     and t.branch_id       = p.branch_id
    join public.orders o
      on o.organization_id = p.organization_id
     and o.id              = p.order_id
     and o.deleted_at is null
     and o.status not in ('cancelled', 'voided')
    where p.organization_id = p_organization_id
      and (p_restaurant_id is null or p.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or p.branch_id     = p_branch_id)
      and p.deleted_at is null
      and p.status = 'completed'
      and (p.created_at at time zone t.zone)::date between t.prev_start and t.cur_end
  ),
  -- MONEY-SETTLEMENT-CONSISTENCY-001 removed the `paid_orders_cur` CTE: a MARKER, and
  -- WINDOW-BOUND (the payment had to land inside the selected range, so an order billed
  -- at a window edge but paid just outside it was reported unpaid). Settlement is a
  -- property of the ORDER, not of the window.
  sales as (
    -- billed sales per bucket = orders NOT voided/cancelled/draft.
    select ow.bucket,
           count(*)::bigint                                                        as order_count,
           count(*) filter (where ow.status = 'completed')::bigint                 as completed_count,
           coalesce(sum(ir.gross_minor), 0)::bigint                                as gross_minor,
           (coalesce(sum(ir.item_discount_minor), 0)
             + coalesce(sum(ow.discount_total_minor), 0))::bigint                  as discount_minor,
           coalesce(sum(ow.subtotal_minor - ow.discount_total_minor), 0)::bigint   as net_minor
    from order_win ow
    left join item_rollup ir on ir.order_id = ow.order_id
    where ow.bucket is not null
      and ow.status not in ('voided', 'cancelled', 'draft')
    group by ow.bucket
  ),
  unpaid_cur as (
    -- Current-window billed orders that still OWE MONEY, by the canonical rule: a
    -- NON-CHARGEABLE zero-total order owes nothing and is not counted; an UNDER-COVERED
    -- order still owes and is counted.
    select count(*)::bigint as unpaid_count
    from order_win ow
    where ow.bucket = 'cur'
      and ow.status not in ('voided', 'cancelled', 'draft')
      and not app.order_is_fully_settled(p_organization_id, ow.order_id)
  ),
  voids_cur as (
    select count(*)::bigint                               as void_count,
           coalesce(sum(ow.grand_total_minor), 0)::bigint as void_total_minor
    from order_win ow
    where ow.bucket = 'cur' and ow.status = 'voided'
  ),
  collected as (
    select bucket,
           coalesce(sum(amount_minor), 0)::bigint                                as collected_minor,
           coalesce(sum(amount_minor) filter (where method = 'cash'), 0)::bigint as cash_minor
    from payment_win
    where bucket is not null
    group by bucket
  ),
  last_cash as (
    select amount_minor as last_cash_payment_minor
    from payment_win
    where bucket = 'cur' and method = 'cash'
    order by created_at desc, id desc
    limit 1
  ),
  tenders_cur as (
    select jsonb_agg(jsonb_build_object('method', method, 'count', cnt, 'total_minor', total_minor)
                     order by method) as tenders
    from (
      select method,
             count(*)::bigint                       as cnt,
             coalesce(sum(amount_minor), 0)::bigint as total_minor
      from payment_win
      where bucket = 'cur'
      group by method
    ) g
  ),
  hourly_net as (
    -- single-day windows only: billed net per branch-local hour.
    select ow.business_hour                                                     as hour,
           coalesce(sum(ow.subtotal_minor - ow.discount_total_minor), 0)::bigint as net_minor
    from order_win ow
    where v_span = 1
      and ow.bucket = 'cur'
      and ow.status not in ('voided', 'cancelled', 'draft')
    group by ow.business_hour
  ),
  hourly_series as (
    -- 24 zero-filled buckets for single-day windows; EMPTY for multi-day.
    select h.hour::int                                                                        as hour,
           coalesce((select hn.net_minor from hourly_net hn where hn.hour = h.hour), 0)::bigint as net_minor
    from generate_series(0, 23) as h(hour)
    where v_span = 1
  ),
  closed_shifts_cur as (
    -- CLOSED/reconciled shifts whose branch-local closed_at day is IN the current
    -- window (tz-less excluded). Reads RF-055 stored expected/counted/variance;
    -- adds opening float (cash_drawer_sessions), opened_by, and duration.
    select s.id                    as shift_id,
           s.branch_id,
           b.name                  as branch_name,
           epc.display_name        as closed_by_name,
           epo.display_name        as opened_by_name,
           coalesce(cds.opening_float_minor, 0)::bigint as opening_float_minor,
           to_char((s.opened_at at time zone t.zone), 'YYYY-MM-DD HH24:MI') as opened_at,
           to_char((s.closed_at at time zone t.zone), 'YYYY-MM-DD HH24:MI') as closed_at,
           (extract(epoch from (s.closed_at - s.opened_at))::bigint / 60)::int as duration_minutes,
           s.expected_total_minor,
           s.counted_total_minor,
           s.variance_minor
    from public.shifts s
    join branch_tz t
      on t.organization_id = s.organization_id
     and t.branch_id       = s.branch_id
    join public.branches b
      on b.organization_id = s.organization_id
     and b.id              = s.branch_id
    left join public.employee_profiles epc
      on epc.organization_id = s.organization_id
     and epc.id             = s.closed_by_employee_profile_id
    left join public.employee_profiles epo
      on epo.organization_id = s.organization_id
     and epo.id             = s.opened_by_employee_profile_id
    left join public.cash_drawer_sessions cds
      on cds.organization_id = s.organization_id
     and cds.shift_id        = s.id
     and cds.deleted_at is null
    where s.organization_id = p_organization_id
      and (p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or s.branch_id     = p_branch_id)
      and s.deleted_at is null
      and s.status in ('closed', 'reconciled')
      and s.closed_at is not null
      and (s.closed_at at time zone t.zone)::date between t.cur_start and t.cur_end
  ),
  shift_sales as (
    -- per-shift paid-order metrics from FK-enforced, server-stamped payments.shift_id
    -- (RF-055/RF-117). Reliable: count(distinct order) / collected / cash.
    select p.shift_id,
           count(distinct p.order_id)::bigint                                     as order_count,
           coalesce(sum(p.amount_minor), 0)::bigint                               as collected_minor,
           coalesce(sum(p.amount_minor) filter (where p.method = 'cash'), 0)::bigint as cash_sales_minor
    from public.payments p
    where p.organization_id = p_organization_id
      and p.deleted_at is null
      and p.status = 'completed'
      and p.shift_id in (select shift_id from closed_shifts_cur)
    group by p.shift_id
  ),
  shift_rows as (
    -- closed shifts enriched with per-shift sales, newest first, capped at 8.
    select cs.*,
           coalesce(ss.order_count, 0)::bigint      as order_count,
           coalesce(ss.collected_minor, 0)::bigint  as collected_minor,
           coalesce(ss.cash_sales_minor, 0)::bigint as cash_sales_minor
    from closed_shifts_cur cs
    left join shift_sales ss on ss.shift_id = cs.shift_id
    order by cs.closed_at desc, cs.shift_id desc
    limit 8
  ),
  open_shifts as (
    -- OPEN shifts NOW in scope (point-in-time count; NOT day/tz bucketed).
    select count(*)::bigint as cnt
    from public.shifts s
    where s.organization_id = p_organization_id
      and (p_restaurant_id is null or s.restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or s.branch_id     = p_branch_id)
      and s.deleted_at is null
      and s.status in ('opening', 'open', 'closing')
  ),
  win as (
    -- representative display window over the SCOPED branches (exact for single-tz).
    select min(cur_start) as range_start, max(cur_end) as range_end
    from branch_tz
    where (p_restaurant_id is null or restaurant_id = p_restaurant_id)
      and (p_branch_id     is null or branch_id     = p_branch_id)
  )
  select jsonb_build_object(
    'current', jsonb_build_object(
      'order_count',             coalesce((select order_count     from sales where bucket = 'cur'), 0),
      'completed_count',         coalesce((select completed_count from sales where bucket = 'cur'), 0),
      'open_count',              coalesce((select order_count - completed_count from sales where bucket = 'cur'), 0),
      'unpaid_count',            coalesce((select unpaid_count    from unpaid_cur), 0),
      'gross_minor',             coalesce((select gross_minor     from sales where bucket = 'cur'), 0),
      'discount_minor',          coalesce((select discount_minor  from sales where bucket = 'cur'), 0),
      'net_minor',               coalesce((select net_minor       from sales where bucket = 'cur'), 0),
      'void_count',              coalesce((select void_count      from voids_cur), 0),
      'void_total_minor',        coalesce((select void_total_minor from voids_cur), 0),
      'collected_minor',         coalesce((select collected_minor from collected where bucket = 'cur'), 0),
      'cash_minor',              coalesce((select cash_minor      from collected where bucket = 'cur'), 0),
      'last_cash_payment_minor', coalesce((select last_cash_payment_minor from last_cash), 0),
      'tenders',                 coalesce((select tenders         from tenders_cur), '[]'::jsonb)),
    'comparison', jsonb_build_object(
      'order_count',     coalesce((select order_count     from sales     where bucket = 'prev'), 0),
      'gross_minor',     coalesce((select gross_minor     from sales     where bucket = 'prev'), 0),
      'net_minor',       coalesce((select net_minor       from sales     where bucket = 'prev'), 0),
      'cash_minor',      coalesce((select cash_minor      from collected where bucket = 'prev'), 0),
      'collected_minor', coalesce((select collected_minor from collected where bucket = 'prev'), 0),
      -- SERVER-B additive keys. Both read the SAME `sales` CTE the
      -- current-window values come from, at bucket='prev', so they are the
      -- prior equal-length branch-local window by construction.
      'completed_count', coalesce((select completed_count from sales where bucket = 'prev'), 0),
      'discount_minor',  coalesce((select discount_minor  from sales where bucket = 'prev'), 0)),
    'hourly', coalesce(
      (select jsonb_agg(jsonb_build_object('hour', hs.hour, 'net_minor', hs.net_minor) order by hs.hour)
       from hourly_series hs),
      '[]'::jsonb),
    'shift_cash', jsonb_build_object(
      'closed_shift_count',  coalesce((select count(*)::int from closed_shifts_cur), 0),
      'open_shift_count',    coalesce((select cnt::int from open_shifts), 0),
      'expected_cash_minor', coalesce((select sum(expected_total_minor)::bigint from closed_shifts_cur), 0),
      'counted_cash_minor',  coalesce((select sum(counted_total_minor)::bigint  from closed_shifts_cur), 0),
      'cash_variance_minor', coalesce((select sum(variance_minor)::bigint       from closed_shifts_cur), 0),
      'last_closed_shift', (
        select jsonb_build_object(
                 'shift_id',            r.shift_id,
                 'branch_id',           r.branch_id,
                 'branch_name',         r.branch_name,
                 'opened_at',           r.opened_at,
                 'closed_at',           r.closed_at,
                 'opened_by_name',      r.opened_by_name,
                 'closed_by_name',      r.closed_by_name,
                 'opening_float_minor', r.opening_float_minor,
                 'duration_minutes',    r.duration_minutes,
                 'order_count',         r.order_count,
                 'collected_minor',     r.collected_minor,
                 'cash_sales_minor',    r.cash_sales_minor,
                 'expected_cash_minor', r.expected_total_minor,
                 'counted_cash_minor',  r.counted_total_minor,
                 'cash_variance_minor', r.variance_minor)
        from shift_rows r
        order by r.closed_at desc, r.shift_id desc
        limit 1),
      'recent_closed_shifts', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'shift_id',            r.shift_id,
                 'branch_id',           r.branch_id,
                 'branch_name',         r.branch_name,
                 'opened_at',           r.opened_at,
                 'closed_at',           r.closed_at,
                 'opened_by_name',      r.opened_by_name,
                 'closed_by_name',      r.closed_by_name,
                 'opening_float_minor', r.opening_float_minor,
                 'duration_minutes',    r.duration_minutes,
                 'order_count',         r.order_count,
                 'collected_minor',     r.collected_minor,
                 'cash_sales_minor',    r.cash_sales_minor,
                 'expected_cash_minor', r.expected_total_minor,
                 'counted_cash_minor',  r.counted_total_minor,
                 'cash_variance_minor', r.variance_minor)
               order by r.closed_at desc, r.shift_id desc)
        from shift_rows r),
        '[]'::jsonb))
  ) || jsonb_build_object(
    'range_start', (select to_char(range_start, 'YYYY-MM-DD') from win),
    'range_end',   (select to_char(range_end,   'YYYY-MM-DD') from win)
  ) into v_result;

  return jsonb_build_object(
    'ok', true,
    'entity', 'owner_report_range',
    'currency_code', v_currency,
    'range', case when v_custom then 'custom' else p_range end
  ) || v_result;
end;
$function$;

-- ---- get_restaurant_receipt_logo (bespoke gate) ---------------------------------
CREATE OR REPLACE FUNCTION app.get_restaurant_receipt_logo(p_organization_id uuid, p_restaurant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor      uuid := app.current_app_user_id();
  v_can_read   boolean;
  v_can_manage boolean;
  v_r          record;
begin
  if v_actor is null then
    raise exception 'get_restaurant_receipt_logo: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null or p_restaurant_id is null then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'restaurant');
  end if;
  -- READ coverage: identical to can_read_restaurant_logo (branch members read;
  -- kitchen_staff excluded from the money-bearing surface).
  select exists (
    select 1 from public.memberships m
    where m.app_user_id     = v_actor
      and m.organization_id = p_organization_id
      and m.status          = 'active'
      and m.deleted_at is null
      and m.role = any (array['org_owner', 'restaurant_owner', 'manager', 'cashier', 'accountant'])
      and (m.restaurant_id is null or m.restaurant_id = p_restaurant_id)
  ) into v_can_read;
  -- ADMIN-126B: a support session reads this surface too. NOTE the rank call
  -- below is deliberately NOT widened: v_can_manage stays false for support, so
  -- the capability flag the client renders and the server's write gate agree.
  if not v_can_read
     and not app.platform_support_can_read_scope(p_organization_id, p_restaurant_id, null) then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'restaurant');
  end if;
  -- MANAGE capability: restaurant-level rank >= manager (identical to the CAS
  -- write gate + can_write_restaurant_logo). Branch-only members => false.
  v_can_manage := app.actor_rank_in_scope(p_organization_id, p_restaurant_id, null) >= 2;
  select r.receipt_logo_path, r.receipt_logo_enabled, r.receipt_logo_version into v_r
    from public.restaurants r
    where r.id = p_restaurant_id and r.organization_id = p_organization_id and r.deleted_at is null;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'not_found', 'entity', 'restaurant');
  end if;
  return jsonb_build_object('ok', true, 'entity', 'restaurant', 'restaurant_id', p_restaurant_id,
    'receipt_logo_path', v_r.receipt_logo_path, 'receipt_logo_enabled', v_r.receipt_logo_enabled,
    'receipt_logo_version', v_r.receipt_logo_version, 'can_manage', v_can_manage);
end;
$function$;

-- ---- list_org_structure (bespoke gate) ------------------------------------------
CREATE OR REPLACE FUNCTION app.list_org_structure(p_organization_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_actor       uuid := app.current_app_user_id();
  v_rank        integer;
  v_org         jsonb;
  v_restaurants jsonb;
begin
  if v_actor is null then
    raise exception 'list_org_structure: authentication required' using errcode = '42501';
  end if;
  if p_organization_id is null then
    raise exception 'list_org_structure: organization_id is required' using errcode = '42501';
  end if;

  -- the caller's highest ACTIVE membership rank ANYWHERE in this org
  -- (deliberately NOT scope-covering — see the header); 0 => not a member.
  select coalesce(max(app.role_rank(m.role)), 0)
    into v_rank
    from public.memberships m
    where m.app_user_id     = v_actor
      and m.organization_id = p_organization_id
      and m.status          = 'active'
      and m.deleted_at is null;
  -- ADMIN-126B: a live, scoped support session reads the org structure with
  -- owner-level READ rank. This function performs no writes, and the rank is
  -- local to it — app.actor_rank_in_scope, which every write gate uses, is
  -- untouched and still returns 0 for a support operator.
  if app.platform_support_can_read_scope(p_organization_id, null, null) then
    v_rank := greatest(v_rank, app.role_rank('org_owner'));
  end if;
  if v_rank = 0 then
    raise exception 'list_org_structure: caller has no active membership in the target organization' using errcode = '42501';
  end if;
  if v_rank < app.role_rank('manager') then  -- cashier/kitchen_staff/accountant excluded
    return jsonb_build_object('ok', false, 'error', 'permission_denied', 'entity', 'org_structure');
  end if;

  -- the organization itself (live only; a tombstoned org is fail-closed).
  select jsonb_build_object('id', o.id, 'name', o.name, 'default_currency', o.default_currency)
    into v_org
    from public.organizations o
    where o.id = p_organization_id and o.deleted_at is null;
  if v_org is null then
    raise exception 'list_org_structure: organization not found' using errcode = '42501';
  end if;

  -- live restaurants with their live branches nested; created_at then name at
  -- both levels (deterministic first-pick for the dashboard).
  select coalesce(jsonb_agg(jsonb_build_object(
           'id', r.id,
           'name', r.name,
           'currency_override', r.currency_override,
           'timezone', r.timezone,
           'status', r.status,
           'branches', coalesce((
             select jsonb_agg(jsonb_build_object(
                      'id', b.id, 'name', b.name, 'timezone', b.timezone, 'status', b.status)
                      order by b.created_at, b.name)
             from public.branches b
             where b.organization_id = r.organization_id
               and b.restaurant_id   = r.id
               and b.deleted_at is null), '[]'::jsonb))
           order by r.created_at, r.name), '[]'::jsonb)
    into v_restaurants
    from public.restaurants r
    where r.organization_id = p_organization_id
      and r.deleted_at is null;

  return jsonb_build_object(
    'ok', true,
    'entity', 'org_structure',
    'organization', v_org,
    'restaurants', v_restaurants,
    'server_ts', now());
end;
$function$;


-- ----------------------------------------------------------------------------
-- 12. Onboarding refuses to run under a support session
--
-- Every other authenticated write path is gated on a membership, a device token
-- or a PIN session, and a support session grants none of those — so they refuse
-- a support operator without any change. This one does not: onboarding
-- deliberately authorizes on a bare auth.uid() because a brand-new user has no
-- tenant yet. It is the only place that has to say no explicitly.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION app.create_organization(p_client_request_id uuid, p_organization_name text, p_organization_slug text, p_restaurant_name text, p_branch_name text, p_currency_code text, p_timezone text, p_default_station_name text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_auth        uuid := auth.uid();
  v_email       text;
  v_app_user    uuid;
  v_currency    text := upper(btrim(coalesce(p_currency_code, '')));
  v_slug        text := lower(btrim(coalesce(p_organization_slug, '')));
  v_station     text := nullif(btrim(coalesce(p_default_station_name, '')), '');
  v_org         uuid;
  v_rest        uuid;
  v_branch      uuid;
  v_station_id  uuid;
  v_membership  uuid;
  v_existing    public.organizations%rowtype;
begin
  -- ADMIN-126 (a0): SUPPORT MODE IS READ-ONLY.
  -- Every other authenticated write path in the system is gated on a
  -- membership, a device token or a PIN session, and a support session grants
  -- none of those — so they refuse a support operator without any change. This
  -- one does not: onboarding deliberately authorizes on a bare auth.uid()
  -- because a brand-new user has no tenant yet. It is therefore the only place
  -- that has to say no explicitly.
  if app.current_support_session() is not null then
    raise exception 'create_organization: platform support mode is read-only'
      using errcode = '42501';
  end if;

  -- ADMIN-126B: SUPPORT MODE IS READ-ONLY.
  if app.current_support_session() is not null then
    raise exception 'create_organization: platform support mode is read-only'
      using errcode = '42501';
  end if;

  -- (a) authentication: the caller MUST be a Supabase Auth principal.
  if v_auth is null then
    raise exception 'create_organization: authentication required' using errcode = '42501';
  end if;
  if p_client_request_id is null then
    raise exception 'create_organization: client_request_id is required' using errcode = '42501';
  end if;

  -- (b) input validation (no money math; integer-free).
  if length(btrim(coalesce(p_organization_name, ''))) = 0 then
    raise exception 'create_organization: organization_name is required' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_restaurant_name, ''))) = 0 then
    raise exception 'create_organization: restaurant_name is required' using errcode = '42501';
  end if;
  if length(btrim(coalesce(p_branch_name, ''))) = 0 then
    raise exception 'create_organization: branch_name is required' using errcode = '42501';
  end if;
  if v_currency !~ '^[A-Z]{3}$' then
    raise exception 'create_organization: currency_code must match ^[A-Z]{3}$ (got %)', p_currency_code using errcode = '42501';
  end if;
  if v_slug !~ '^[a-z0-9]+(-[a-z0-9]+)*$' then
    raise exception 'create_organization: organization_slug must match ^[a-z0-9]+(-[a-z0-9]+)*$ (got %)', p_organization_slug using errcode = '42501';
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names where name = p_timezone) then
    raise exception 'create_organization: timezone % is not a valid IANA timezone', p_timezone using errcode = '42501';
  end if;

  -- (c) bootstrap the caller's app_user (derive ONLY from auth.uid(); never input).
  select au.id into v_app_user
  from public.app_users au
  where au.auth_user_id = v_auth;

  if v_app_user is null then
    v_email := lower(btrim(coalesce(auth.jwt() ->> 'email', '')));
    if length(v_email) = 0 then
      raise exception 'create_organization: an email claim is required to provision an account' using errcode = '42501';
    end if;
    begin
      insert into public.app_users (email, auth_user_id)
      values (v_email, v_auth)
      returning id into v_app_user;
    exception when unique_violation then
      -- race or pre-existing email: re-resolve by auth principal; if the email
      -- belongs to an unlinked/other account, fail clearly (no shared accounts).
      select au.id into v_app_user from public.app_users au where au.auth_user_id = v_auth;
      if v_app_user is null then
        raise exception 'create_organization: an account already exists for this email' using errcode = '42501';
      end if;
    end;
  end if;

  -- (d) idempotency replay: same caller + same client_request_id.
  select * into v_existing
  from public.organizations o
  where o.created_by_app_user_id = v_app_user
    and o.creation_request_id    = p_client_request_id;

  if found then
    return app.create_organization_replay(v_existing, p_organization_name, v_slug, v_currency, v_app_user);
  end if;

  -- (e) create the organization (provenance + idem key recorded).
  begin
    insert into public.organizations (name, slug, default_currency, created_by_app_user_id, creation_request_id)
    values (btrim(p_organization_name), v_slug, v_currency, v_app_user, p_client_request_id)
    returning id into v_org;
  exception when unique_violation then
    -- A concurrent call for the SAME (caller, request_id) won the idem index.
    -- RF090-B1: re-load the FULL existing org and replay through the SAME helper
    -- as the pre-check — it runs the identical conflict comparison (so a racing
    -- conflicting payload still fails) and returns the STORED slug.
    select * into v_existing
    from public.organizations o
    where o.created_by_app_user_id = v_app_user and o.creation_request_id = p_client_request_id;
    if found then
      return app.create_organization_replay(v_existing, p_organization_name, v_slug, v_currency, v_app_user);
    end if;
    -- otherwise it was a global slug collision with a DIFFERENT org.
    raise exception 'create_organization: organization slug "%" is already taken', v_slug using errcode = '42501';
  end;

  -- (f) first restaurant + branch (+ optional default station).
  insert into public.restaurants (organization_id, name, timezone)
  values (v_org, btrim(p_restaurant_name), p_timezone)
  returning id into v_rest;

  insert into public.branches (organization_id, restaurant_id, name, timezone)
  values (v_org, v_rest, btrim(p_branch_name), p_timezone)
  returning id into v_branch;

  if v_station is not null then
    insert into public.stations (organization_id, restaurant_id, branch_id, name)
    values (v_org, v_rest, v_branch, v_station)
    returning id into v_station_id;
  end if;

  -- (g) first membership: org_owner (membership-scoped role, NOT a global role).
  --     restaurant_id/branch_id NULL => org-wide. Role is hardcoded; no role,
  --     app_user_id, organization_id, or platform input is ever accepted.
  insert into public.memberships (app_user_id, organization_id, restaurant_id, branch_id, role, status)
  values (v_app_user, v_org, null, null, 'org_owner', 'active')
  returning id into v_membership;

  -- (h) append-only audit event (D-013). Actor is the app_user (no device/PIN yet).
  insert into public.audit_events
    (organization_id, restaurant_id, branch_id, actor_app_user_id, device_id, action, reason, old_values, new_values)
  values
    (v_org, v_rest, v_branch, v_app_user, null, 'organization.created', null, null,
     jsonb_build_object(
       'client_request_id', p_client_request_id,
       'organization_name', btrim(p_organization_name),
       'slug', v_slug,
       'default_currency', v_currency,
       'restaurant_name', btrim(p_restaurant_name),
       'branch_name', btrim(p_branch_name),
       'default_station_name', v_station,
       'owner_membership_role', 'org_owner'));

  return jsonb_build_object(
    'ok', true, 'idempotent_replay', false,
    'organization_id', v_org, 'restaurant_id', v_rest, 'branch_id', v_branch,
    'station_id', v_station_id, 'membership_id', v_membership,
    'app_user_id', v_app_user, 'slug', v_slug);
end;
$function$;
