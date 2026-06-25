-- RF-109 Stage 1 -- Backend menu schema + RLS foundation.
--
-- Ratified by DECISION D-031 (per-ticket M6 backend-surface ADR). Entities/fields
-- owned by DOMAIN_MODEL section 4 (reconciled under RF-109); isolation control T-013
-- (SECURITY_AND_THREAT_MODEL section 14). Stage 1 implements SCHEMA + RLS ONLY:
-- NO management RPCs, NO public.menu_* wrappers, NO sync_pull changes (later stages).
--
-- Invariants honored:
--   D-001/D-002/D-012  organization_id isolation + composite same-org FKs (RF-014 pattern).
--   D-007              integer minor-unit money only (bigint _minor); NO float/numeric/decimal/money.
--   D-008              NO FK from order snapshot rows to the live menu (orders never recompute).
--   D-011/D-012        direct writes denied-by-policy + REVOKED; RLS enabled+forced; deny-by-default.
--   D-017              snake_case plural tables; id uuid pk; _minor money; created/updated/deleted_at.
--   D-020              deleted_at tombstones -- SELECT policies do NOT filter deleted_at (sync needs them later).
--   D-026              platform_admin is NEVER on the tenant RLS path (app.is_platform_admin() not referenced).
--   D-028              accountant is read-only (no write path anywhere).
--   T-003              menu rows carry money; kitchen_staff is EXCLUDED from menu reads on every path.

-- ---------------------------------------------------------------------------
-- 0. Same-org composite-FK target on stations (RF-109-Q1 / D-031).
--    stations had only `primary key (id)`; add unique(organization_id, id) so
--    menu_items.default_station_id can use the same-org composite FK pattern
--    (mirrors restaurants/branches). id is already unique, so the pair is
--    trivially unique -- additive and safe on existing rows.
-- ---------------------------------------------------------------------------
alter table stations
  add constraint stations_organization_id_id_key unique (organization_id, id);

-- ---------------------------------------------------------------------------
-- 1. menu_categories  (restaurant-scoped; branch_id = nullable scope override)
-- ---------------------------------------------------------------------------
create table menu_categories (
  id               uuid        not null default gen_random_uuid(),
  organization_id  uuid        not null references organizations (id) on delete restrict,
  restaurant_id    uuid        not null,
  branch_id        uuid,
  name             text        not null check (length(btrim(name)) > 0),
  display_order    integer     not null default 0,
  is_active        boolean     not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  primary key (id),
  unique (organization_id, id),
  foreign key (organization_id, restaurant_id)
    references restaurants (organization_id, id) on delete restrict,
  -- branch_id nullable: MATCH SIMPLE skips this FK when branch_id is null
  -- (restaurant-scoped); when set, the branch must be same org + restaurant.
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict
);

-- ---------------------------------------------------------------------------
-- 2. menu_items  (a sellable product; integer-minor money + currency)
-- ---------------------------------------------------------------------------
create table menu_items (
  id                 uuid        not null default gen_random_uuid(),
  organization_id    uuid        not null references organizations (id) on delete restrict,
  restaurant_id      uuid        not null,
  branch_id          uuid,
  menu_category_id   uuid        not null,
  default_station_id uuid,
  name               text        not null check (length(btrim(name)) > 0),
  description        text,
  base_price_minor   bigint      not null check (base_price_minor >= 0),       -- D-007 integer minor; absolute >= 0
  currency_code      char(3)     not null check (currency_code ~ '^[A-Z]{3}$'),-- ISO 4217 uppercase
  display_order      integer     not null default 0,
  is_active          boolean     not null default true,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  deleted_at         timestamptz,
  primary key (id),
  unique (organization_id, id),
  foreign key (organization_id, restaurant_id)
    references restaurants (organization_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict,
  foreign key (organization_id, menu_category_id)
    references menu_categories (organization_id, id) on delete restrict,
  -- default_station_id nullable: MATCH SIMPLE skips when null; when set, the
  -- station must be in the same organization (RF-109-Q1; same-org composite FK).
  foreign key (organization_id, default_station_id)
    references stations (organization_id, id) on delete restrict
);

-- ---------------------------------------------------------------------------
-- 3. item_sizes  (child of menu_items; signed price delta)
-- ---------------------------------------------------------------------------
create table item_sizes (
  id                uuid        not null default gen_random_uuid(),
  organization_id   uuid        not null references organizations (id) on delete restrict,
  restaurant_id     uuid        not null,
  branch_id         uuid,
  menu_item_id      uuid        not null,
  name              text        not null check (length(btrim(name)) > 0),
  price_delta_minor bigint      not null default 0,   -- D-007 integer minor; SIGNED (may be negative)
  display_order     integer     not null default 0,
  is_active         boolean     not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  primary key (id),
  unique (organization_id, id),
  foreign key (organization_id, restaurant_id)
    references restaurants (organization_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict,
  foreign key (organization_id, menu_item_id)
    references menu_items (organization_id, id) on delete restrict
);

-- ---------------------------------------------------------------------------
-- 4. item_variants  (child of menu_items; signed price delta)
-- ---------------------------------------------------------------------------
create table item_variants (
  id                uuid        not null default gen_random_uuid(),
  organization_id   uuid        not null references organizations (id) on delete restrict,
  restaurant_id     uuid        not null,
  branch_id         uuid,
  menu_item_id      uuid        not null,
  name              text        not null check (length(btrim(name)) > 0),
  price_delta_minor bigint      not null default 0,   -- D-007 integer minor; SIGNED (may be negative)
  display_order     integer     not null default 0,
  is_active         boolean     not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  primary key (id),
  unique (organization_id, id),
  foreign key (organization_id, restaurant_id)
    references restaurants (organization_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict,
  foreign key (organization_id, menu_item_id)
    references menu_items (organization_id, id) on delete restrict
);

-- ---------------------------------------------------------------------------
-- 5. modifiers  (child of menu_items; selection rules stored, not enforced here)
--    Direct item->modifiers FK only (D-031: NO many-to-many groups in RF-109).
-- ---------------------------------------------------------------------------
create table modifiers (
  id               uuid        not null default gen_random_uuid(),
  organization_id  uuid        not null references organizations (id) on delete restrict,
  restaurant_id    uuid        not null,
  branch_id        uuid,
  menu_item_id     uuid        not null,
  name             text        not null check (length(btrim(name)) > 0),
  selection_type   text        not null default 'single' check (selection_type in ('single', 'multiple')),
  min_select       integer     not null default 0 check (min_select >= 0),
  max_select       integer     check (max_select is null or max_select >= 0),
  is_required      boolean     not null default false,
  display_order    integer     not null default 0,
  is_active        boolean     not null default true,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  deleted_at       timestamptz,
  primary key (id),
  unique (organization_id, id),
  foreign key (organization_id, restaurant_id)
    references restaurants (organization_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict,
  foreign key (organization_id, menu_item_id)
    references menu_items (organization_id, id) on delete restrict
);

-- ---------------------------------------------------------------------------
-- 6. modifier_options  (child of modifiers; signed price delta)
-- ---------------------------------------------------------------------------
create table modifier_options (
  id                uuid        not null default gen_random_uuid(),
  organization_id   uuid        not null references organizations (id) on delete restrict,
  restaurant_id     uuid        not null,
  branch_id         uuid,
  modifier_id       uuid        not null,
  name              text        not null check (length(btrim(name)) > 0),
  price_delta_minor bigint      not null default 0,   -- D-007 integer minor; SIGNED (may be negative)
  display_order     integer     not null default 0,
  is_active         boolean     not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  primary key (id),
  unique (organization_id, id),
  foreign key (organization_id, restaurant_id)
    references restaurants (organization_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict,
  foreign key (organization_id, modifier_id)
    references modifiers (organization_id, id) on delete restrict
);

-- ---------------------------------------------------------------------------
-- 7. Indexes (tenant filtering + same-org parent FK support)
-- ---------------------------------------------------------------------------
create index menu_categories_organization_id_idx  on menu_categories  (organization_id);
create index menu_categories_org_restaurant_idx   on menu_categories  (organization_id, restaurant_id);

create index menu_items_organization_id_idx       on menu_items       (organization_id);
create index menu_items_org_restaurant_idx        on menu_items       (organization_id, restaurant_id);
create index menu_items_org_category_idx          on menu_items       (organization_id, menu_category_id);

create index item_sizes_organization_id_idx       on item_sizes       (organization_id);
create index item_sizes_org_restaurant_idx        on item_sizes       (organization_id, restaurant_id);
create index item_sizes_org_item_idx              on item_sizes       (organization_id, menu_item_id);

create index item_variants_organization_id_idx    on item_variants    (organization_id);
create index item_variants_org_restaurant_idx     on item_variants    (organization_id, restaurant_id);
create index item_variants_org_item_idx           on item_variants    (organization_id, menu_item_id);

create index modifiers_organization_id_idx        on modifiers        (organization_id);
create index modifiers_org_restaurant_idx         on modifiers        (organization_id, restaurant_id);
create index modifiers_org_item_idx               on modifiers        (organization_id, menu_item_id);

create index modifier_options_organization_id_idx on modifier_options (organization_id);
create index modifier_options_org_restaurant_idx  on modifier_options (organization_id, restaurant_id);
create index modifier_options_org_modifier_idx    on modifier_options (organization_id, modifier_id);

-- ---------------------------------------------------------------------------
-- 8. updated_at triggers (shared app.set_updated_at, RF-014)
-- ---------------------------------------------------------------------------
create trigger menu_categories_set_updated_at  before update on menu_categories
  for each row execute function app.set_updated_at();
create trigger menu_items_set_updated_at       before update on menu_items
  for each row execute function app.set_updated_at();
create trigger item_sizes_set_updated_at       before update on item_sizes
  for each row execute function app.set_updated_at();
create trigger item_variants_set_updated_at    before update on item_variants
  for each row execute function app.set_updated_at();
create trigger modifiers_set_updated_at        before update on modifiers
  for each row execute function app.set_updated_at();
create trigger modifier_options_set_updated_at before update on modifier_options
  for each row execute function app.set_updated_at();

-- ---------------------------------------------------------------------------
-- 9. RLS: enable + force + explicit per-command policies (RF-059 template).
--
--    SELECT: scope-gated to the FIVE non-kitchen tenant roles
--      (org_owner / restaurant_owner / manager / cashier / accountant) via
--      app.has_role_in_scope -- this is the same role set as app.can_read_financials.
--      kitchen_staff is EXCLUDED because menu rows carry money (base_price_minor /
--      price_delta_minor) and a kitchen principal must not read any money figure
--      (T-003). KDS gets item names from order snapshots, never the live menu.
--    SELECT does NOT filter deleted_at: tombstones must remain visible to permitted
--      readers for sync (D-020); later stages pull them via sync_pull.
--    INSERT/UPDATE/DELETE: denied-by-policy AND revoked -- all writes go through the
--      SECURITY DEFINER menu_* RPCs in a later stage (D-011/D-012).
--    platform_admin is NOT referenced here (D-026): it is never a tenant RLS path.
-- ---------------------------------------------------------------------------

-- menu_categories
alter table menu_categories enable row level security;
alter table menu_categories force  row level security;
create policy menu_categories_sel on menu_categories for select to authenticated
  using (organization_id = app.current_org_id()
         and app.has_role_in_scope(organization_id, restaurant_id, branch_id,
               'org_owner', 'restaurant_owner', 'manager', 'cashier', 'accountant'));
create policy menu_categories_ins_deny on menu_categories for insert to authenticated with check (false);
create policy menu_categories_upd_deny on menu_categories for update to authenticated using (false) with check (false);
create policy menu_categories_del_deny on menu_categories for delete to authenticated using (false);

-- menu_items
alter table menu_items enable row level security;
alter table menu_items force  row level security;
create policy menu_items_sel on menu_items for select to authenticated
  using (organization_id = app.current_org_id()
         and app.has_role_in_scope(organization_id, restaurant_id, branch_id,
               'org_owner', 'restaurant_owner', 'manager', 'cashier', 'accountant'));
create policy menu_items_ins_deny on menu_items for insert to authenticated with check (false);
create policy menu_items_upd_deny on menu_items for update to authenticated using (false) with check (false);
create policy menu_items_del_deny on menu_items for delete to authenticated using (false);

-- item_sizes
alter table item_sizes enable row level security;
alter table item_sizes force  row level security;
create policy item_sizes_sel on item_sizes for select to authenticated
  using (organization_id = app.current_org_id()
         and app.has_role_in_scope(organization_id, restaurant_id, branch_id,
               'org_owner', 'restaurant_owner', 'manager', 'cashier', 'accountant'));
create policy item_sizes_ins_deny on item_sizes for insert to authenticated with check (false);
create policy item_sizes_upd_deny on item_sizes for update to authenticated using (false) with check (false);
create policy item_sizes_del_deny on item_sizes for delete to authenticated using (false);

-- item_variants
alter table item_variants enable row level security;
alter table item_variants force  row level security;
create policy item_variants_sel on item_variants for select to authenticated
  using (organization_id = app.current_org_id()
         and app.has_role_in_scope(organization_id, restaurant_id, branch_id,
               'org_owner', 'restaurant_owner', 'manager', 'cashier', 'accountant'));
create policy item_variants_ins_deny on item_variants for insert to authenticated with check (false);
create policy item_variants_upd_deny on item_variants for update to authenticated using (false) with check (false);
create policy item_variants_del_deny on item_variants for delete to authenticated using (false);

-- modifiers
alter table modifiers enable row level security;
alter table modifiers force  row level security;
create policy modifiers_sel on modifiers for select to authenticated
  using (organization_id = app.current_org_id()
         and app.has_role_in_scope(organization_id, restaurant_id, branch_id,
               'org_owner', 'restaurant_owner', 'manager', 'cashier', 'accountant'));
create policy modifiers_ins_deny on modifiers for insert to authenticated with check (false);
create policy modifiers_upd_deny on modifiers for update to authenticated using (false) with check (false);
create policy modifiers_del_deny on modifiers for delete to authenticated using (false);

-- modifier_options
alter table modifier_options enable row level security;
alter table modifier_options force  row level security;
create policy modifier_options_sel on modifier_options for select to authenticated
  using (organization_id = app.current_org_id()
         and app.has_role_in_scope(organization_id, restaurant_id, branch_id,
               'org_owner', 'restaurant_owner', 'manager', 'cashier', 'accountant'));
create policy modifier_options_ins_deny on modifier_options for insert to authenticated with check (false);
create policy modifier_options_upd_deny on modifier_options for update to authenticated using (false) with check (false);
create policy modifier_options_del_deny on modifier_options for delete to authenticated using (false);

-- ---------------------------------------------------------------------------
-- 10. Grants: authenticated keeps SELECT only (RLS-gated). Direct writes are
--     revoked (RF-014 grant -> RF-059 revoke lineage). anon is never granted.
-- ---------------------------------------------------------------------------
grant select, insert, update, delete on menu_categories  to authenticated;
grant select, insert, update, delete on menu_items       to authenticated;
grant select, insert, update, delete on item_sizes       to authenticated;
grant select, insert, update, delete on item_variants    to authenticated;
grant select, insert, update, delete on modifiers        to authenticated;
grant select, insert, update, delete on modifier_options to authenticated;

revoke insert, update, delete on menu_categories  from authenticated;
revoke insert, update, delete on menu_items       from authenticated;
revoke insert, update, delete on item_sizes       from authenticated;
revoke insert, update, delete on item_variants    from authenticated;
revoke insert, update, delete on modifiers        from authenticated;
revoke insert, update, delete on modifier_options from authenticated;
