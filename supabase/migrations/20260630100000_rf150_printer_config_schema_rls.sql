-- ============================================================================
-- RF-150 — Printer configuration: tenant-scoped printer DEVICES + station ROUTES
--          (schema + RLS). PRINTERS_AND_HARDWARE_SPEC §2/§3/§4/§6; DECISIONS
--          D-001/D-002/D-012/D-017/D-020; RISK R-003.
-- ============================================================================
-- The frozen PRINTERS_AND_HARDWARE_SPEC anticipates branch-level, tenant-scoped
-- printer CONFIGURATION: which printers exist (device class, transport, paper
-- width, receipt-vs-kitchen ROLE — §2/§3/§4), and the per-branch station ->
-- destination ROUTING map (§6). That configuration was entirely missing from the
-- schema (no printer_* tables; devices.device_type is only 'pos'/'kds'). This
-- migration adds it. It does NOT add the on-device print SPOOL (`print_jobs`): per
-- spec §7 the spool is a LOCAL Drift/SQLite concern and is NOT cloud-synced.
--
-- Scope: CONFIGURATION ONLY. No native print transport, no drawer kick, no
-- "printing succeeded" — those stay deferred behind the replaceable adapter
-- (D-009; Q-006/Q-015). A future native local print bridge consumes this config.
--
-- Isolation (R-003, D-012): every row carries organization_id + restaurant_id +
-- branch_id; composite same-org FKs to branches/stations/printer_devices make a
-- cross-organization OR cross-branch reference STRUCTURALLY IMPOSSIBLE (layer 4).
-- RLS is enabled + forced with explicit per-command policies (the RF-059 shape):
-- SELECT is org + scope gated; direct writes are DENIED — configuration writes are
-- owner/manager-only SECURITY DEFINER RPCs (RF-150 rpcs migration). No money columns
-- anywhere (printer config touches no money; D-007/T-003 spirit).
--
-- FORWARD-ONLY (Supabase replays on db reset). Manual teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. stations: add the composite same-org/branch UNIQUE so printer_routes can
--    structurally pin a route's station to its exact (org, restaurant, branch).
--    Additive: `id` is already unique, so this composite is trivially satisfied
--    for every existing row; it only adds a same-branch composite-FK target.
-- ----------------------------------------------------------------------------
alter table public.stations
  add constraint stations_org_rest_branch_id_key unique (organization_id, restaurant_id, branch_id, id);

-- ----------------------------------------------------------------------------
-- 1. printer_devices — a configured printer (or printer ROLE) at a branch.
--    "receipt" vs "kitchen" are ROLES, not SKUs (spec §2). connection_type is the
--    transport (spec §3). paper_width 58/80mm (spec §4, 80mm default). The
--    connection_config jsonb holds transport specifics (e.g. {"host","port"} for
--    network) — LAN-only, NO tenant data leaves via the printer path (spec §3
--    SECURITY). No money columns.
-- ----------------------------------------------------------------------------
create table printer_devices (
  id                uuid        not null default gen_random_uuid(),
  organization_id   uuid        not null references organizations (id) on delete restrict,
  restaurant_id     uuid        not null,
  branch_id         uuid        not null,
  display_name      text        not null check (length(btrim(display_name)) > 0),
  connection_type   text        not null check (connection_type in ('network', 'usb', 'bluetooth')),
  role              text        not null check (role in ('receipt', 'kitchen')),
  paper_width       text        not null default '80mm' check (paper_width in ('58mm', '80mm')),
  connection_config jsonb       not null default '{}'::jsonb check (jsonb_typeof(connection_config) = 'object'),
  is_enabled        boolean     not null default true,
  revision          integer     not null default 1,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  primary key (id),
  unique (organization_id, id),
  unique (organization_id, restaurant_id, branch_id, id),
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict
);

comment on table printer_devices is
  'RF-150 (PRINTERS_AND_HARDWARE_SPEC §2/§3/§4): a configured printer at a branch. role = receipt|kitchen (a ROLE, not a SKU); connection_type = network|usb|bluetooth (transport); paper_width 58|80mm. connection_config jsonb holds transport specifics (LAN-only, no tenant data). Tenant-scoped (org/restaurant/branch) with composite same-org FK to branches. CONFIGURATION ONLY — no print transport/spool here (the spool is local, spec §7). No money columns. Writes are owner/manager-only RPCs (RF-150).';
comment on column printer_devices.connection_config is
  'RF-150: transport specifics as a JSON object (e.g. {"host":"10.0.0.50","port":9100} for network). MUST be a JSON object. Never carries tenant business data or money.';
comment on column printer_devices.deleted_at is
  'Soft-delete tombstone (D-020). NULL = live row.';

-- ----------------------------------------------------------------------------
-- 2. printer_routes — the per-branch station -> printer routing map (spec §6).
--    A station MAY route to several printers (redundancy); a (station, printer)
--    edge is unique among LIVE routes. Composite FKs to BOTH stations and
--    printer_devices on (org, restaurant, branch, id) force the station and the
--    printer into the SAME branch (structural; no cross-branch routing).
-- ----------------------------------------------------------------------------
create table printer_routes (
  id                uuid        not null default gen_random_uuid(),
  organization_id   uuid        not null references organizations (id) on delete restrict,
  restaurant_id     uuid        not null,
  branch_id         uuid        not null,
  station_id        uuid        not null,
  printer_device_id uuid        not null,
  is_enabled        boolean     not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  deleted_at        timestamptz,
  primary key (id),
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id, station_id)
    references stations (organization_id, restaurant_id, branch_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id, printer_device_id)
    references printer_devices (organization_id, restaurant_id, branch_id, id) on delete restrict
);

comment on table printer_routes is
  'RF-150 (PRINTERS_AND_HARDWARE_SPEC §6): the per-branch station -> printer routing map. Composite FKs to stations AND printer_devices on (org, restaurant, branch, id) force a route''s station and printer into the SAME branch (structural; D-012 layer 4). A station may route to several printers; the partial unique index keeps a (station, printer) edge unique among LIVE (deleted_at IS NULL) routes. Writes are owner/manager-only RPCs (RF-150).';

-- one LIVE route per (station, printer) edge; re-creatable after a soft-delete.
create unique index printer_routes_station_printer_live_key
  on printer_routes (organization_id, restaurant_id, branch_id, station_id, printer_device_id)
  where deleted_at is null;

-- ----------------------------------------------------------------------------
-- 3. Indexes (tenant filtering + FK delete-restrict support). The composite
--    UNIQUEs already index the org-prefixed keys for printer_devices; add the
--    route FK-backing indexes + the printer back-reference.
-- ----------------------------------------------------------------------------
create index printer_routes_org_rest_branch_station_idx on printer_routes (organization_id, restaurant_id, branch_id, station_id);
create index printer_routes_org_rest_branch_printer_idx on printer_routes (organization_id, restaurant_id, branch_id, printer_device_id);

-- ----------------------------------------------------------------------------
-- 4. updated_at triggers (D-017).
-- ----------------------------------------------------------------------------
create trigger printer_devices_set_updated_at before update on printer_devices
  for each row execute function app.set_updated_at();
create trigger printer_routes_set_updated_at before update on printer_routes
  for each row execute function app.set_updated_at();

-- ----------------------------------------------------------------------------
-- 5. RLS (D-012 layer 1, RF-059 per-command shape). Enabled + FORCED. SELECT is
--    org + scope gated; direct INSERT/UPDATE/DELETE are DENIED (writes are the
--    owner/manager SECURITY DEFINER RPCs in the RF-150 rpcs migration — those run
--    as the BYPASSRLS owner and are unaffected by these DENY policies). The
--    RF-019 default-deny detector requires every organization_id-bearing table to
--    be enabled+forced with >=1 policy; these satisfy it.
-- ----------------------------------------------------------------------------
alter table printer_devices enable row level security;
alter table printer_devices force  row level security;
alter table printer_routes  enable row level security;
alter table printer_routes  force  row level security;

create policy printer_devices_sel on printer_devices for select to authenticated
  using (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));
create policy printer_devices_ins_deny on printer_devices for insert to authenticated with check (false);
create policy printer_devices_upd_deny on printer_devices for update to authenticated using (false) with check (false);
create policy printer_devices_del_deny on printer_devices for delete to authenticated using (false);

create policy printer_routes_sel on printer_routes for select to authenticated
  using (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));
create policy printer_routes_ins_deny on printer_routes for insert to authenticated with check (false);
create policy printer_routes_upd_deny on printer_routes for update to authenticated using (false) with check (false);
create policy printer_routes_del_deny on printer_routes for delete to authenticated using (false);

-- ----------------------------------------------------------------------------
-- 6. Grants. Least privilege: authenticated may SELECT only (RLS-scoped). Writes
--    are NEVER granted directly — they flow through the owner/manager RPCs.
-- ----------------------------------------------------------------------------
grant select on printer_devices to authenticated;
grant select on printer_routes  to authenticated;

-- ============================================================================
-- DOWN (manual; Supabase is forward-only — `supabase db reset` replays):
--   drop table if exists printer_routes;
--   drop table if exists printer_devices;
--   alter table public.stations drop constraint if exists stations_org_rest_branch_id_key;
-- ============================================================================
