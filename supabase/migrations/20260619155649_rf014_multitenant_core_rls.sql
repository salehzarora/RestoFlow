-- ============================================================================
-- RF-014 — First multi-tenant migration: organizational hierarchy + RLS skeleton
-- ============================================================================
-- Tenant-isolation foundation for RestoFlow (milestone M0B). Creates the
-- organizational hierarchy
--
--     organizations -> restaurants -> branches -> stations
--
-- with organization_id as the PRIMARY tenant-isolation boundary (DECISION
-- D-001) inside the Platform -> Organization -> Restaurant -> Branch ->
-- Device/Station hierarchy (DECISION D-002), a baseline deny-by-default RLS
-- skeleton (DECISION D-012 layer 1) and DB constraints as the final safety
-- boundary (DECISION D-012 layer 4). Naming follows DECISION D-017; soft-delete
-- tombstones follow DECISION D-020.
--
-- RISK R-003 (CRITICAL): an RLS bug here would leak cross-tenant data. Defences:
--   * RLS is ENABLED *and* FORCED on every table.
--   * Policies deny by default: no tenant context => zero rows.
--   * Cross-org parent references are made STRUCTURALLY IMPOSSIBLE via composite
--     same-org foreign keys (SECURITY_AND_THREAT_MODEL structural cross-tenant
--     prevention; DECISION D-012 layer 4).
--
-- ----------------------------------------------------------------------------
-- INTERIM TENANT CONTEXT — READ BEFORE EXTENDING
-- ----------------------------------------------------------------------------
-- Membership (RF-015) and Supabase Auth / JWT (RF-050) do NOT exist yet, so the
-- frozen docs' server-side, membership/JWT-derived tenant scope cannot be wired
-- now. This migration therefore uses an INTERIM Postgres GUC,
-- `app.current_organization_id`, read through a SINGLE helper
-- `app.current_org_id()`. Supersession is centralised in that one helper body:
--   * RF-015 replaces the body with a membership-derived resolver.
--   * RF-050 / RF-059 swap it to a JWT / auth.uid()-derived scope (a client can
--     never forge it) and deliver the full per-command policy matrix plus the
--     human RLS sign-off.
-- Only ONE function body changes on supersession — never the policies on every
-- table.
--
-- This migration is FORWARD-ONLY (Supabase replays migrations on `db reset`).
-- A manual teardown for documented reversibility is at the foot of the file.
-- This file ships reference/config tables only: NO money columns, NO sync
-- columns (device_id/local_operation_id/revision — DOMAIN_MODEL sync-column
-- rule), NO identity/membership/audit/device tables (RF-015/016/017).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Helper schema. NOT exposed via PostgREST: supabase/config.toml api.schemas is
-- ["public","graphql_public"], so nothing in `app` is reachable over the Data
-- API. Helpers live here (never in `public`) so the tenant-context resolver can
-- never be called as a REST RPC.
-- ----------------------------------------------------------------------------
create schema if not exists app;

comment on schema app is
  'RestoFlow internal helpers (RF-014). Not exposed via the Data API. Houses the interim tenant-context resolver app.current_org_id() and the updated_at trigger function.';

-- Interim tenant-context resolver (see header). An unset or empty GUC yields
-- NULL, and `col = NULL` is never TRUE, so every policy denies by default
-- (zero rows). STABLE: the value is constant within a single statement. This
-- body is the SINGLE supersession point for RF-015 / RF-050 / RF-059.
create or replace function app.current_org_id()
  returns uuid
  language sql
  stable
as $$
  select nullif(current_setting('app.current_organization_id', true), '')::uuid
$$;

comment on function app.current_org_id() is
  'INTERIM (RF-014): resolves the active tenant (organization) id from GUC app.current_organization_id. Superseded by membership (RF-015) then JWT/auth.uid() (RF-050/RF-059). Unset => NULL => deny-by-default.';

-- updated_at maintenance, attached as a BEFORE UPDATE trigger on each table.
create or replace function app.set_updated_at()
  returns trigger
  language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

comment on function app.set_updated_at() is
  'BEFORE UPDATE trigger function: stamps updated_at = now() (DECISION D-017 timestamp convention).';

-- ----------------------------------------------------------------------------
-- organizations — the tenant root (DECISION D-003). Its own `id` IS the
-- organization_id every other tenant-scoped row carries (DECISION D-001), so it
-- has no parent and no organization_id column of its own.
-- ----------------------------------------------------------------------------
create table organizations (
  id                uuid        primary key default gen_random_uuid(),
  name              text        not null check (length(btrim(name)) > 0),
  slug              text        not null unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$'),
  default_currency  char(3)     not null check (default_currency ~ '^[A-Z]{3}$'),
  country_code      char(2)              check (country_code ~ '^[A-Z]{2}$'),
  status            text        not null default 'active' check (status in ('active', 'suspended')),
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz
);

comment on table organizations is
  'Tenant root (DECISION D-003). organizations.id is the organization_id tenant-isolation key (DECISION D-001) carried by every other tenant-scoped table.';
comment on column organizations.default_currency is
  'ISO-4217 alpha-3 code (interim text + regex check; full ISO-4217 lookup is OPEN QUESTION Q-007). NOT a money amount — no _minor money columns in this migration.';
comment on column organizations.deleted_at is
  'Soft-delete tombstone (DECISION D-020). NULL = live row. Sync-relevant deletions set this instead of hard-deleting.';
comment on column organizations.slug is
  'Globally unique tenant/URL identifier. INTERIM decision: uniqueness is unconditional, so a slug is NOT reusable after a soft-delete (the D-020 tombstone row persists). If reuse-after-offboarding is later required, revisit under data-retention/offline-sync (OPEN QUESTION Q-005) — it would become a partial unique index WHERE deleted_at IS NULL.';

-- ----------------------------------------------------------------------------
-- restaurants — belongs to exactly one organization.
-- The UNIQUE (organization_id, id) is the composite-FK target that lets child
-- tables prove a parent lives in the SAME organization.
-- ----------------------------------------------------------------------------
create table restaurants (
  id                 uuid        not null default gen_random_uuid(),
  organization_id    uuid        not null references organizations (id) on delete restrict,
  name               text        not null check (length(btrim(name)) > 0),
  currency_override  char(3)              check (currency_override ~ '^[A-Z]{3}$'),
  timezone           text,
  status             text        not null default 'active' check (status in ('active', 'suspended')),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  primary key (id),
  unique (organization_id, id)
);

comment on table restaurants is
  'A restaurant brand within an organization. organization_id is NOT NULL (DECISION D-001). UNIQUE (organization_id, id) is the same-org composite-FK target for branches.';

-- ----------------------------------------------------------------------------
-- branches — belongs to one restaurant within one organization.
-- The composite FK (organization_id, restaurant_id) -> restaurants
-- (organization_id, id) makes a cross-organization parent reference
-- STRUCTURALLY IMPOSSIBLE. UNIQUE (organization_id, restaurant_id, id) is the
-- composite-FK target that pins a station's full ancestry.
-- ----------------------------------------------------------------------------
create table branches (
  id               uuid        not null default gen_random_uuid(),
  organization_id  uuid        not null references organizations (id) on delete restrict,
  restaurant_id    uuid        not null,
  name             text        not null check (length(btrim(name)) > 0),
  address          text,
  timezone         text,
  receipt_prefix   text,
  status           text        not null default 'active' check (status in ('active', 'suspended')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  primary key (id),
  unique (organization_id, restaurant_id, id),
  foreign key (organization_id, restaurant_id)
    references restaurants (organization_id, id) on delete restrict
);

comment on table branches is
  'A physical location of a restaurant. Composite FK (organization_id, restaurant_id) -> restaurants(organization_id, id) makes cross-org parent references structurally impossible (DECISION D-012 layer 4).';

-- ----------------------------------------------------------------------------
-- stations — a KDS/prep station within one branch.
-- The composite FK (organization_id, restaurant_id, branch_id) -> branches
-- (organization_id, restaurant_id, id) pins the station's full org/restaurant/
-- branch ancestry in a single structural constraint.
-- ----------------------------------------------------------------------------
create table stations (
  id               uuid        not null default gen_random_uuid(),
  organization_id  uuid        not null references organizations (id) on delete restrict,
  restaurant_id    uuid        not null,
  branch_id        uuid        not null,
  name             text        not null check (length(btrim(name)) > 0),
  type             text,
  display_order    integer     not null default 0,
  is_active        boolean     not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  primary key (id),
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict
);

comment on table stations is
  'A KDS/prep station within a branch. Composite FK (organization_id, restaurant_id, branch_id) -> branches(...) pins the full same-org ancestry (DECISION D-012 layer 4).';

-- ----------------------------------------------------------------------------
-- Indexes. PK and UNIQUE constraints already index `id` and the org-prefixed
-- composite keys (covering tenant filtering and FK delete-restrict checks on
-- organizations/restaurants/branches). Add only the indexes those do not cover:
-- stations has no org-prefixed unique, so index it for tenant filtering and to
-- support the branch -> stations delete-restrict check.
-- ----------------------------------------------------------------------------
create index stations_organization_id_idx on stations (organization_id);
create index stations_org_restaurant_branch_idx on stations (organization_id, restaurant_id, branch_id);

-- ----------------------------------------------------------------------------
-- updated_at triggers (DECISION D-017).
-- ----------------------------------------------------------------------------
create trigger organizations_set_updated_at before update on organizations
  for each row execute function app.set_updated_at();
create trigger restaurants_set_updated_at before update on restaurants
  for each row execute function app.set_updated_at();
create trigger branches_set_updated_at before update on branches
  for each row execute function app.set_updated_at();
create trigger stations_set_updated_at before update on stations
  for each row execute function app.set_updated_at();

-- ----------------------------------------------------------------------------
-- Row-Level Security (DECISION D-012 layer 1). Every table is ENABLED *and*
-- FORCED: FORCE makes even the table owner policy-bound (only true superusers
-- and BYPASSRLS roles are exempt — that is why isolation tests must run as a
-- non-privileged role such as `authenticated`). With no matching policy the
-- default is deny.
--
-- INTERIM single FOR ALL policy per table (using + with check). RF-059 splits
-- these into the full per-command (select/insert/update/delete) matrix with the
-- human RLS sign-off. The tenant predicate references the single helper
-- app.current_org_id(), so superseding the tenant-context source is a one-line
-- change to that helper, not 4 x N policy rewrites.
-- ----------------------------------------------------------------------------
alter table organizations enable row level security;
alter table organizations force  row level security;
alter table restaurants   enable row level security;
alter table restaurants   force  row level security;
alter table branches      enable row level security;
alter table branches      force  row level security;
alter table stations      enable row level security;
alter table stations      force  row level security;

-- organizations: the tenant root is matched on its own id.
create policy organizations_tenant_isolation on organizations
  for all
  to authenticated
  using      (id = app.current_org_id())
  with check (id = app.current_org_id());

-- restaurants / branches / stations: matched on organization_id.
create policy restaurants_tenant_isolation on restaurants
  for all
  to authenticated
  using      (organization_id = app.current_org_id())
  with check (organization_id = app.current_org_id());

create policy branches_tenant_isolation on branches
  for all
  to authenticated
  using      (organization_id = app.current_org_id())
  with check (organization_id = app.current_org_id());

create policy stations_tenant_isolation on stations
  for all
  to authenticated
  using      (organization_id = app.current_org_id())
  with check (organization_id = app.current_org_id());

-- ----------------------------------------------------------------------------
-- Grants. Least privilege: only `authenticated` (never `anon`). RLS still
-- constrains which rows that role can see/modify. `authenticated` also needs
-- USAGE on schema app + EXECUTE on the resolver because RLS policy expressions
-- are evaluated with the querying role's privileges. The service_role
-- (BYPASSRLS, server-side only — DECISION D-011) is intentionally NOT granted
-- here; it gains table access only when server code requires it.
-- ----------------------------------------------------------------------------
grant usage on schema app to authenticated;
grant execute on function app.current_org_id() to authenticated;

grant select, insert, update, delete on organizations to authenticated;
grant select, insert, update, delete on restaurants   to authenticated;
grant select, insert, update, delete on branches       to authenticated;
grant select, insert, update, delete on stations        to authenticated;

-- ============================================================================
-- DOWN (manual) — documented reversibility. Supabase migrations are
-- forward-only (the cleanliness gate is `supabase db reset`, which replays from
-- empty); run the statements below by hand to fully undo this migration. Order
-- is reverse-dependency. Triggers and policies drop with their tables.
-- ============================================================================
-- drop table if exists stations;
-- drop table if exists branches;
-- drop table if exists restaurants;
-- drop table if exists organizations;
-- drop function if exists app.set_updated_at();
-- drop function if exists app.current_org_id();
-- drop schema if exists app;   -- only once nothing else lives in `app`
