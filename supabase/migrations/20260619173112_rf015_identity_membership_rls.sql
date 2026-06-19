-- ============================================================================
-- RF-015 — Identity & membership schema + membership-scoped RLS
-- ============================================================================
-- Builds on RF-014 (organizations -> restaurants -> branches -> stations). Adds
-- the human-identity plane and turns the interim tenant resolver into a
-- MEMBERSHIP-DERIVED one, then narrows the existing core hierarchy rows by the
-- caller's membership scope. Keeps the six identity concepts distinct
-- (DECISION D-005); roles are membership-scoped, never a global column on the
-- user (DECISION D-004). `platform_admin` is NOT a membership role and is carried
-- by a SEPARATE, organization_id-free `platform_admin_grants` table (DECISION
-- D-026). Carries RISK R-003 (CRITICAL): an RLS/scoping bug leaks cross-tenant
-- data — requires human RLS sign-off before merge.
--
-- ----------------------------------------------------------------------------
-- INTERIM TENANT CONTEXT — evolution of RF-014
-- ----------------------------------------------------------------------------
-- RF-014 shipped `app.current_org_id()` reading a raw GUC. RF-015 (as RF-014's
-- header anticipated) makes it MEMBERSHIP-DERIVED: the selected org GUC
-- (`app.current_organization_id`) is honoured ONLY if the current user
-- (`app.current_app_user_id`) holds an ACTIVE, non-deleted membership in it;
-- otherwise the resolver returns NULL (deny-by-default). It NEVER picks an
-- arbitrary org from the user's memberships. Two interim GUCs are used until
-- Supabase Auth / JWT exists (RF-050 swaps the user source to auth.uid()):
--   * app.current_app_user_id    -> app.current_app_user_id()  (GUC only)
--   * app.current_organization_id -> app.current_org_id()       (membership-validated)
-- The FULL per-command + per-role policy matrix and human RLS sign-off remain
-- RF-059; this migration enforces ORG isolation + the MINIMAL restaurant/branch
-- narrowing required so a restaurant-scoped cashier cannot reach another
-- restaurant in the same org (Codex RF-015 required adjustment).
--
-- SECURITY DEFINER NOTE: the resolver/scope helpers read `memberships`, which is
-- itself RLS-protected. They are SECURITY DEFINER with a LOCKED, empty
-- search_path so (a) the membership lookup does not recurse through the
-- memberships policy, and (b) the path cannot be hijacked. They are STABLE,
-- READ-ONLY, take no caller identity as an argument (identity always comes from
-- the GUC via app.current_app_user_id()), and grant NO privilege beyond the
-- internal membership-validation lookup.
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual teardown at the foot.
-- Out of scope (other tickets): devices/pairing/pin-sessions (RF-016),
-- audit_events (RF-017), reusable isolation harness (RF-019), JWT/auth.uid
-- (RF-050), full role-per-command matrix + sign-off (RF-059), platform-admin
-- enforcement/audit (RF-060). No business/money/sync/app code here.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. Interim current-user resolver. GUC-only (no table read) => no recursion,
--    no SECURITY DEFINER needed. Superseded by auth.uid() at RF-050.
-- ----------------------------------------------------------------------------
create or replace function app.current_app_user_id()
  returns uuid
  language sql
  stable
  set search_path = ''
as $$
  select nullif(current_setting('app.current_app_user_id', true), '')::uuid
$$;

comment on function app.current_app_user_id() is
  'INTERIM (RF-015): the current app user id from GUC app.current_app_user_id. Superseded by auth.uid() (RF-050). Unset => NULL.';

-- ----------------------------------------------------------------------------
-- 2. app_users — the global person / auth principal (identity concept #1).
--    NOT tenant-scoped: no organization_id, NO global role column (roles are
--    membership-scoped, D-004), no password/PIN/plaintext secret (auth lives in
--    the provider). `id` is standalone now; RF-050 aligns it with auth.uid().
-- ----------------------------------------------------------------------------
create table app_users (
  id            uuid        primary key default gen_random_uuid(),
  email         text        not null unique check (length(btrim(email)) > 0 and email = lower(email)),
  display_name  text,
  is_active     boolean     not null default true,
  mfa_enabled   boolean     not null default false,  -- placeholder only (Q-008); no enforcement here
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

comment on table app_users is
  'Global person/auth principal (D-005 #1). NOT tenant-scoped (no organization_id); a user belongs to many orgs only via memberships. No global role column (D-004); no password/PIN/plaintext (auth lives in the provider).';

-- ----------------------------------------------------------------------------
-- 3. memberships — a user's scoped relationship to an organization (concept #2),
--    carrying a membership-scoped role. Tenant-scoped (organization_id NOT NULL),
--    optionally narrowed to restaurant/branch. Cross-org parent references are
--    structurally impossible via composite same-org FKs (D-012 layer 4).
-- ----------------------------------------------------------------------------
create table memberships (
  id               uuid        not null default gen_random_uuid(),
  app_user_id      uuid        not null references app_users (id) on delete restrict,
  organization_id  uuid        not null references organizations (id) on delete restrict,
  restaurant_id    uuid,                              -- null => org-wide within the role
  branch_id        uuid,                              -- null => not branch-narrowed
  role             text        not null
                     check (role in ('org_owner','restaurant_owner','manager','cashier','kitchen_staff','accountant')),
  status           text        not null default 'active' check (status in ('active','revoked')),
  permissions      jsonb       not null default '{}'::jsonb,   -- optional fine-grained overrides (unused interim)
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  primary key (id),
  unique (organization_id, id),                       -- same-org composite-FK target for employee_profiles
  -- a branch-scoped membership must name its restaurant (no branch without restaurant)
  constraint memberships_branch_requires_restaurant check (branch_id is null or restaurant_id is not null),
  -- same-org restaurant scope (skipped when restaurant_id is null — MATCH SIMPLE)
  constraint memberships_restaurant_same_org
    foreign key (organization_id, restaurant_id) references restaurants (organization_id, id) on delete restrict,
  -- same-org branch scope, pinning org+restaurant+branch (skipped when branch_id is null)
  constraint memberships_branch_same_org
    foreign key (organization_id, restaurant_id, branch_id) references branches (organization_id, restaurant_id, id) on delete restrict
);

comment on table memberships is
  'Scoped user<->organization relationship (D-005 #2) carrying a membership-scoped role (D-004). role CHECK excludes platform_admin (D-026). status is an INTERIM label set (active/revoked) — not in the D-018 proposed set, cross-ref threat T-005; do not treat as frozen.';
comment on column memberships.role is
  'One of the six tenant role keys (D-004/D-026). accountant is reserved now (read-only per D-028; ships-or-not is Q-017) with NO behavior here. platform_admin is intentionally NOT accepted (D-026).';

create index memberships_app_user_id_idx  on memberships (app_user_id);
create index memberships_app_user_org_idx on memberships (app_user_id, organization_id);
create index memberships_org_scope_idx    on memberships (organization_id, restaurant_id, branch_id);

-- ----------------------------------------------------------------------------
-- 4. employee_profiles — employment record within an organization (concept #3),
--    distinct from app_users and memberships. Tenant-scoped. PIN/session/device
--    behavior is RF-016; pin_credential_ref is a reference/hash placeholder only.
-- ----------------------------------------------------------------------------
create table employee_profiles (
  id                 uuid        not null default gen_random_uuid(),
  organization_id    uuid        not null references organizations (id) on delete restrict,
  restaurant_id      uuid,
  branch_id          uuid,
  app_user_id        uuid        references app_users (id) on delete restrict,  -- may be null (PIN-only staff need not hold a full account)
  membership_id      uuid,                                                      -- authoritative role+scope link (REQUIRED for PIN-capable at RF-016)
  employee_number    text,
  display_name       text,
  pin_credential_ref text,                                                      -- reference/hash ONLY; never plaintext; PIN mechanism = RF-016
  employment_status  text        not null default 'active'
                       check (employment_status in ('active','suspended','terminated')),
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  primary key (id),
  unique (organization_id, employee_number),
  constraint employee_profiles_branch_requires_restaurant check (branch_id is null or restaurant_id is not null),
  constraint employee_profiles_restaurant_same_org
    foreign key (organization_id, restaurant_id) references restaurants (organization_id, id) on delete restrict,
  constraint employee_profiles_branch_same_org
    foreign key (organization_id, restaurant_id, branch_id) references branches (organization_id, restaurant_id, id) on delete restrict,
  -- the linked membership must belong to the SAME organization (skipped when membership_id is null)
  constraint employee_profiles_membership_same_org
    foreign key (organization_id, membership_id) references memberships (organization_id, id) on delete restrict
);

comment on table employee_profiles is
  'Employment record within an organization (D-005 #3); distinct from app_users and memberships. Tenant-scoped. pin_credential_ref is a reference/hash placeholder only (never plaintext); PIN/session behavior is RF-016. employment_status is an INTERIM label set (cross-ref T-005); not frozen.';

create index employee_profiles_org_idx           on employee_profiles (organization_id);
create index employee_profiles_app_user_idx      on employee_profiles (app_user_id);
create index employee_profiles_membership_id_idx on employee_profiles (organization_id, membership_id);  -- backs the ON DELETE RESTRICT same-org membership FK

-- ----------------------------------------------------------------------------
-- 5. platform_admin_grants — the platform plane (D-026). DELIBERATELY carries
--    NO organization_id / restaurant_id / branch_id: it is NOT a tenant
--    membership and never satisfies tenant RLS. Full enforcement/audit = RF-060.
-- ----------------------------------------------------------------------------
create table platform_admin_grants (
  id           uuid        primary key default gen_random_uuid(),
  app_user_id  uuid        not null references app_users (id) on delete restrict,
  status       text        not null default 'active' check (status in ('active','suspended','revoked')),
  granted_by   uuid        not null references app_users (id) on delete restrict,
  granted_at   timestamptz not null default now(),
  revoked_by   uuid        references app_users (id) on delete restrict,
  revoked_at   timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
  -- DELIBERATELY NO organization_id/restaurant_id/branch_id/device_id/station_id (D-026):
  -- platform-scoped, outside the tenant hierarchy and the D-001 isolation boundary.
);

comment on table platform_admin_grants is
  'Platform-admin authority (D-026): a separate, privileged, audited path — NOT a tenant membership. Carries NO organization_id/restaurant_id/branch_id and never satisfies tenant RLS. Enforcement/audit/MFA (Q-008) are RF-060.';

create index platform_admin_grants_app_user_idx   on platform_admin_grants (app_user_id);
create index platform_admin_grants_granted_by_idx on platform_admin_grants (granted_by);  -- backs ON DELETE RESTRICT FK to app_users
create index platform_admin_grants_revoked_by_idx on platform_admin_grants (revoked_by);  -- backs ON DELETE RESTRICT FK to app_users

-- ----------------------------------------------------------------------------
-- 6. Membership-derived tenant resolver (REPLACES the RF-014 GUC-only body).
--    Returns the SELECTED org iff the current user holds an active, non-deleted
--    membership in it; else NULL. Never returns an arbitrary org. SECURITY
--    DEFINER + locked empty search_path so the membership read does not recurse
--    through the memberships policy and the path cannot be hijacked.
-- ----------------------------------------------------------------------------
create or replace function app.current_org_id()
  returns uuid
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select m.organization_id
  from public.memberships m
  where m.app_user_id = app.current_app_user_id()
    and m.organization_id = nullif(current_setting('app.current_organization_id', true), '')::uuid
    and m.status = 'active'
    and m.deleted_at is null
  limit 1
$$;

comment on function app.current_org_id() is
  'INTERIM (RF-015): the active tenant id = the SELECTED org (GUC app.current_organization_id) validated against an ACTIVE, non-deleted membership for app.current_app_user_id(). Returns NULL if unset/invalid; never an arbitrary org. SECURITY DEFINER (membership lookup only). Superseded by JWT/auth.uid() at RF-050/RF-059.';

-- ----------------------------------------------------------------------------
-- 7. Scope predicate: does the current user's active membership in the active
--    org cover the target (organization, restaurant, branch)? Enforces the
--    MINIMAL restaurant/branch narrowing required by RF-015:
--      * org-wide membership (restaurant_id NULL)  -> all rows in the org
--      * restaurant-scoped (restaurant_id = R)      -> only restaurant R's rows
--      * branch-scoped (branch_id = B)              -> R's restaurant-level rows + branch B
--    target_restaurant/target_branch NULL means "the row is at that-or-broader
--    level" (e.g. the organization row), which any in-org membership may see.
--    SECURITY DEFINER + locked search_path (same rationale as the resolver).
-- ----------------------------------------------------------------------------
create or replace function app.has_scope(target_org uuid, target_restaurant uuid, target_branch uuid)
  returns boolean
  language sql
  stable
  security definer
  set search_path = ''
as $$
  select exists (
    select 1
    from public.memberships m
    where m.app_user_id = app.current_app_user_id()
      and m.organization_id = app.current_org_id()
      and m.organization_id = target_org
      and m.status = 'active'
      and m.deleted_at is null
      and (m.restaurant_id is null or target_restaurant is null or m.restaurant_id = target_restaurant)
      and (m.branch_id     is null or target_branch     is null or m.branch_id     = target_branch)
  )
$$;

comment on function app.has_scope(uuid, uuid, uuid) is
  'INTERIM (RF-015): true iff the current user has an active membership in the active org whose scope covers (target_org, target_restaurant, target_branch). Restaurant-level denial is enforced now; the full per-role/per-command matrix is RF-059.';

-- ----------------------------------------------------------------------------
-- 8. Helper grants: least privilege. Revoke the default PUBLIC execute and grant
--    only to authenticated (RLS policy expressions run as the querying role).
-- ----------------------------------------------------------------------------
revoke all on function app.current_app_user_id()        from public;
revoke all on function app.current_org_id()             from public;
revoke all on function app.has_scope(uuid, uuid, uuid)  from public;
grant execute on function app.current_app_user_id()       to authenticated;
grant execute on function app.current_org_id()            to authenticated;
grant execute on function app.has_scope(uuid, uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- 9. RLS on the new identity tables: ENABLE + FORCE, deny-by-default.
-- ----------------------------------------------------------------------------
alter table app_users             enable row level security;
alter table app_users             force  row level security;
alter table memberships           enable row level security;
alter table memberships           force  row level security;
alter table employee_profiles     enable row level security;
alter table employee_profiles     force  row level security;
alter table platform_admin_grants enable row level security;
alter table platform_admin_grants force  row level security;

-- app_users: self-only (interim). Cross-member visibility/management is RPC/RF-059.
create policy app_users_self on app_users
  for all
  to authenticated
  using      (id = app.current_app_user_id())
  with check (id = app.current_app_user_id());

-- memberships: a user always sees their OWN memberships (bootstrap: needed to
-- enumerate/select an active org before current_org_id() can resolve); plus
-- in-scope memberships within the active org. Writes are confined to the active
-- org + scope (true role-gating of membership management is RF-059).
create policy memberships_scoped on memberships
  for all
  to authenticated
  using (
    app_user_id = app.current_app_user_id()
    or (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id))
  )
  with check (
    organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id)
  );

-- employee_profiles: scoped to the active org + membership scope.
create policy employee_profiles_scoped on employee_profiles
  for all
  to authenticated
  using      (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id))
  with check (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));

-- platform_admin_grants: NO policy for `authenticated` and (below) NO table
-- grant => the ordinary tenant path is fully denied. The privileged platform
-- path is RF-060. This guarantees a grant can never satisfy tenant RLS.

-- ----------------------------------------------------------------------------
-- 10. Narrow the EXISTING RF-014 core hierarchy policies by membership scope.
--     organizations stays `id = current_org_id()` (any in-org member may see the
--     org row; current_org_id() is now membership-validated). restaurants/
--     branches/stations gain has_scope() so a restaurant-scoped cashier cannot
--     reach another restaurant in the same org (Codex RF-015 required adjustment).
--     The RF-014 migration file is unchanged; we drop+recreate its policies here.
-- ----------------------------------------------------------------------------
drop policy restaurants_tenant_isolation on restaurants;
create policy restaurants_tenant_isolation on restaurants
  for all
  to authenticated
  using      (organization_id = app.current_org_id() and app.has_scope(organization_id, id, null))
  with check (organization_id = app.current_org_id() and app.has_scope(organization_id, id, null));

drop policy branches_tenant_isolation on branches;
create policy branches_tenant_isolation on branches
  for all
  to authenticated
  using      (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, id))
  with check (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, id));

drop policy stations_tenant_isolation on stations;
create policy stations_tenant_isolation on stations
  for all
  to authenticated
  using      (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id))
  with check (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));

-- ----------------------------------------------------------------------------
-- 11. Table grants: least privilege, authenticated only (never anon).
--     platform_admin_grants is intentionally NOT granted (platform plane).
-- ----------------------------------------------------------------------------
grant select, insert, update, delete on app_users         to authenticated;
grant select, insert, update, delete on memberships       to authenticated;
grant select, insert, update, delete on employee_profiles to authenticated;

-- ----------------------------------------------------------------------------
-- 12. updated_at triggers (DECISION D-017), reusing app.set_updated_at() (RF-014).
-- ----------------------------------------------------------------------------
create trigger app_users_set_updated_at             before update on app_users             for each row execute function app.set_updated_at();
create trigger memberships_set_updated_at           before update on memberships           for each row execute function app.set_updated_at();
create trigger employee_profiles_set_updated_at     before update on employee_profiles     for each row execute function app.set_updated_at();
create trigger platform_admin_grants_set_updated_at before update on platform_admin_grants for each row execute function app.set_updated_at();

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; the cleanliness gate is
-- `supabase db reset`. To fully undo by hand, in reverse-dependency order:
-- ----------------------------------------------------------------------------
-- -- restore the RF-014 (org-only) core policies:
-- drop policy stations_tenant_isolation on stations;
-- create policy stations_tenant_isolation on stations for all to authenticated
--   using (organization_id = app.current_org_id()) with check (organization_id = app.current_org_id());
-- drop policy branches_tenant_isolation on branches;
-- create policy branches_tenant_isolation on branches for all to authenticated
--   using (organization_id = app.current_org_id()) with check (organization_id = app.current_org_id());
-- drop policy restaurants_tenant_isolation on restaurants;
-- create policy restaurants_tenant_isolation on restaurants for all to authenticated
--   using (organization_id = app.current_org_id()) with check (organization_id = app.current_org_id());
-- -- restore the RF-014 GUC-only resolver:
-- create or replace function app.current_org_id() returns uuid language sql stable as $$
--   select nullif(current_setting('app.current_organization_id', true), '')::uuid $$;
-- drop function if exists app.has_scope(uuid, uuid, uuid);
-- drop function if exists app.current_app_user_id();
-- drop table if exists platform_admin_grants;
-- drop table if exists employee_profiles;
-- drop table if exists memberships;
-- drop table if exists app_users;
-- ============================================================================
