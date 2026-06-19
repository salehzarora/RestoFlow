-- ============================================================================
-- RF-016 — Device identity, pairing, device sessions, PIN sessions + RLS
-- ============================================================================
-- Builds on RF-014 (org->restaurant->branch->station) and RF-015 (app_users,
-- memberships, employee_profiles, membership-derived tenant resolver + scope).
-- Adds the four device/session identity concepts (DECISION D-005 #4/#5/#6 +
-- pairing lifecycle): a DEVICE is a non-human identity; a device SESSION is
-- bound to a paired+authorized device; a human PIN SESSION layers ONLY on an
-- active device session. All four tables are tenant + BRANCH scoped (D-001/D-002):
-- organization_id, restaurant_id, branch_id are NOT NULL, and cross-org/branch
-- references are made structurally impossible by composite same-org FKs
-- (D-012 layer 4). Carries RISK R-003 (CRITICAL) + device threats TH-3/TH-5 /
-- RISK R-007 — requires human sign-off before merge.
--
-- ----------------------------------------------------------------------------
-- SCOPE BOUNDARIES (what this migration deliberately does NOT do)
-- ----------------------------------------------------------------------------
-- RF-016 ships SCHEMA + minimal DB INTEGRITY GUARDS only. It does NOT imply the
-- final pairing/PIN workflow. Deferred elsewhere:
--   * PIN verification, attempt limits, lockout, offline-validity window -> RF-051 / Q-009
--   * audited pair_device / revoke_device / start_pin_session RPC bodies and the
--     full pairing transition authorization matrix -> RF-050 / RF-051 / STATE_MACHINES
--   * Supabase Auth / JWT / auth.uid() and device-session-as-RLS-principal
--     (NO app.current_device_id/_session_id GUCs here) -> RF-050
--   * audit_events -> RF-017 ; Drift/local outbox -> RF-018 ; reusable isolation
--     harness + CI DB wiring -> RF-019 ; full role matrix -> RF-059 ; platform
--     admin audit -> RF-060 ; local data-at-rest/device secrets -> RF-021
-- The pin_session backing guard re-validates ONLY at WRITE time: later suspending/
-- revoking a parent device_session or pairing does NOT cascade-invalidate an
-- already-active child pin_session. That runtime/offline revocation is
-- server-authoritative + rejected-on-reconnect (RISK R-007, Q-009) — NOT a DB
-- BEFORE-trigger concern — and is deferred to RF-051.
-- Reuses the RF-015 resolver/scope helpers UNCHANGED (app.current_app_user_id(),
-- app.current_org_id(), app.has_scope()) so all RF-014/RF-015 tests still pass.
-- FORWARD-ONLY (Supabase replays on db reset); manual teardown at the foot.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. RF-015 employee_profiles gains a same-org composite-FK target (A2).
--    Additive only; the RF-015 migration FILE is NOT edited. (id is already
--    unique via PK, so (organization_id, id) is trivially unique — no data risk.)
--    This lets pin_sessions reference an employee_profile with a same-org FK.
-- ----------------------------------------------------------------------------
alter table employee_profiles add constraint employee_profiles_org_id_key unique (organization_id, id);

-- ----------------------------------------------------------------------------
-- 1. devices — a DEVICE IDENTITY (POS/KDS), NOT a human (D-005 #4, D-006).
--    Deliberately has NO app_user_id, NO role/membership column, NO PIN fields,
--    NO plaintext secret (only a credential REFERENCE). Branch-scoped (A3).
-- ----------------------------------------------------------------------------
create table devices (
  id                    uuid        not null default gen_random_uuid(),
  organization_id       uuid        not null references organizations (id) on delete restrict,
  restaurant_id         uuid        not null,
  branch_id             uuid        not null,
  device_type           text        not null check (device_type in ('pos', 'kds')),  -- INTERIM label set (ASSUMPTION; not in D-018) — do not treat as frozen
  label                 text,
  device_credential_ref text,        -- reference/hash ONLY; never a plaintext secret (D-011); real credential is OS-secure-stored on device (RF-021)
  last_seen_at          timestamptz,
  is_active             boolean     not null default true,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  deleted_at            timestamptz,
  primary key (id),
  unique (organization_id, restaurant_id, branch_id, id),                 -- full-scope composite-FK target for pairings/sessions
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict
);

comment on table devices is
  'Device identity (D-005 #4): a POS/KDS device with its own credential reference and limited permissions — NOT a human (no app_user_id/role). Branch-scoped (D-001/D-002). device_type is an INTERIM CHECK (pos/kds), not frozen. device_credential_ref is a reference/hash only (D-011); never a plaintext secret.';

-- ----------------------------------------------------------------------------
-- 2. device_pairings — controlled enrollment lifecycle (D-006). Short-lived,
--    EXPIRING enrollment code stored as a HASH/reference only (A5). status uses
--    the D-018 enumeration (PROPOSED, approved into the RF-004 baseline; do not
--    add/rename/repurpose). Transition AUTHORIZATION + audit is RPC (RF-050/051).
-- ----------------------------------------------------------------------------
create table device_pairings (
  id                   uuid        not null default gen_random_uuid(),
  organization_id      uuid        not null references organizations (id) on delete restrict,
  restaurant_id        uuid        not null,
  branch_id            uuid        not null,
  device_id            uuid        not null,
  enrollment_code_hash text,        -- HASH/reference ONLY (A5); never a plaintext enrollment code
  code_expires_at      timestamptz,
  status               text        not null default 'code_issued'
                         check (status in ('code_issued','pending','paired','active','suspended','revoked','code_expired','rejected')),
  paired_at            timestamptz,
  revoked_at           timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  deleted_at           timestamptz,
  primary key (id),
  unique (organization_id, restaurant_id, branch_id, id),
  unique (organization_id, restaurant_id, branch_id, device_id, id),  -- device-scoped composite-FK target: lets a session pin the pairing to its OWN device
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict,
  -- the paired device must be in the SAME org+restaurant+branch (structural; D-012 layer 4)
  foreign key (organization_id, restaurant_id, branch_id, device_id)
    references devices (organization_id, restaurant_id, branch_id, id) on delete restrict
);

comment on table device_pairings is
  'Device enrollment lifecycle (D-006). status = D-018 PROPOSED enum (code_issued->pending->paired->active->suspended->revoked; +code_expired,rejected), approved into the RF-004 baseline; do not add/rename/repurpose. enrollment_code_hash is a hash/reference only (never plaintext). Expiry/transition authorization + audit are RPC (RF-050/RF-051).';

-- ----------------------------------------------------------------------------
-- 3. device_sessions — an authenticated session bound to a device + its
--    authorizing pairing (D-005 #5). Token stored as reference/hash only.
--    is_active/revoked_at represent validity; the OFFLINE-validity behavior of
--    expires_at is DEFERRED (Q-009/RF-051) — the column exists, not its policy.
-- ----------------------------------------------------------------------------
create table device_sessions (
  id                uuid        not null default gen_random_uuid(),
  organization_id   uuid        not null references organizations (id) on delete restrict,
  restaurant_id     uuid        not null,
  branch_id         uuid        not null,
  device_id         uuid        not null,
  device_pairing_id uuid        not null,
  session_token_ref text,        -- reference/hash ONLY; never a plaintext token
  started_at        timestamptz not null default now(),
  expires_at        timestamptz,  -- offline-validity behavior DEFERRED to Q-009/RF-051
  revoked_at        timestamptz,
  is_active         boolean     not null default true,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  primary key (id),
  unique (organization_id, restaurant_id, branch_id, id),
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict,
  foreign key (organization_id, restaurant_id, branch_id, device_id)
    references devices (organization_id, restaurant_id, branch_id, id) on delete restrict,
  -- session must be authorized by a pairing of its OWN device (device_id pinned), in the SAME branch (structural; DOMAIN_MODEL §3.5)
  foreign key (organization_id, restaurant_id, branch_id, device_id, device_pairing_id)
    references device_pairings (organization_id, restaurant_id, branch_id, device_id, id) on delete restrict
);

comment on table device_sessions is
  'Authenticated device session (D-005 #5), bound to a device + the pairing that authorized it. session_token_ref is a reference/hash only (never plaintext). expires_at exists but the offline-validity window/behavior is DEFERRED (Q-009/RF-051).';

-- ----------------------------------------------------------------------------
-- 4. pin_sessions — a human PIN session (D-005 #6) layered ONLY on an active
--    device session. Stores NO PIN material (the credential ref lives on
--    employee_profiles.pin_credential_ref). resolved_membership_id is NOT NULL
--    (A7) — a PIN session deterministically carries one role+scope (the
--    resolution PRECEDENCE/logic is RF-051; only the column+FK ship here).
-- ----------------------------------------------------------------------------
create table pin_sessions (
  id                    uuid        not null default gen_random_uuid(),
  organization_id       uuid        not null references organizations (id) on delete restrict,
  restaurant_id         uuid        not null,
  branch_id             uuid        not null,
  device_session_id     uuid        not null,
  employee_profile_id   uuid        not null,
  resolved_membership_id uuid       not null,
  started_at            timestamptz not null default now(),
  expires_at            timestamptz,  -- offline/idle validity DEFERRED to Q-009/RF-051
  ended_at              timestamptz,
  is_active             boolean     not null default true,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  primary key (id),
  unique (organization_id, restaurant_id, branch_id, id),
  foreign key (organization_id, restaurant_id, branch_id)
    references branches (organization_id, restaurant_id, id) on delete restrict,
  -- PIN session sits on a device session in the SAME branch (structural)
  foreign key (organization_id, restaurant_id, branch_id, device_session_id)
    references device_sessions (organization_id, restaurant_id, branch_id, id) on delete restrict,
  -- employee + resolved membership must be in the SAME organization (structural)
  foreign key (organization_id, employee_profile_id)
    references employee_profiles (organization_id, id) on delete restrict,
  foreign key (organization_id, resolved_membership_id)
    references memberships (organization_id, id) on delete restrict
);

comment on table pin_sessions is
  'Human PIN session (D-005 #6) layered ONLY on an active device session (enforced by the app.enforce_pin_session_backing trigger). Stores NO PIN (credential ref is on employee_profiles). resolved_membership_id NOT NULL (A7). PIN verification/attempt-limit/lockout/offline behavior is DEFERRED (RF-051).';

-- ----------------------------------------------------------------------------
-- 5. Indexes — FK-backing (delete-restrict probes) + tenant/branch filtering.
--    The unique(org,restaurant,branch,id) keys already index the org-prefixed
--    paths; add indexes for the parent-id FK columns not otherwise covered.
-- ----------------------------------------------------------------------------
create index device_pairings_device_idx       on device_pairings (organization_id, restaurant_id, branch_id, device_id);
create index device_sessions_device_idx       on device_sessions (organization_id, restaurant_id, branch_id, device_id);
create index device_sessions_pairing_idx      on device_sessions (organization_id, restaurant_id, branch_id, device_pairing_id);
create index pin_sessions_device_session_idx  on pin_sessions (organization_id, restaurant_id, branch_id, device_session_id);
create index pin_sessions_employee_idx        on pin_sessions (organization_id, employee_profile_id);
create index pin_sessions_membership_idx      on pin_sessions (organization_id, resolved_membership_id);

-- ----------------------------------------------------------------------------
-- 6. Minimal DB integrity guards (RF-016 acceptance). These enforce DATA
--    INTEGRITY only — not the authoritative workflow (who/when/audit = RPC).
-- ----------------------------------------------------------------------------

-- 6a. Expired enrollment code cannot COMPLETE pairing. An expired code may only
--     move to code_expired; it must NOT enter pending/paired/active. Inspects
--     only NEW/OLD (no table reads) so no SECURITY DEFINER is needed.
create or replace function app.enforce_pairing_code_expiry()
  returns trigger
  language plpgsql
  set search_path = ''
as $$
begin
  -- Gate ONLY the genuine enrollment-completion edges that consume a live code:
  -- a fresh INSERT into a redeemed state, or code_issued -> pending/paired/active.
  -- Do NOT gate post-enrollment lifecycle transitions (paired->active, and the
  -- canon-legal suspended->active re-enable per STATE_MACHINES §9) — those never
  -- consume the enrollment code and a long-live device's code_expires_at is
  -- naturally in the past.
  if NEW.code_expires_at is not null
     and NEW.code_expires_at < now()
     and NEW.status in ('pending', 'paired', 'active')
     and (TG_OP = 'INSERT' or OLD.status = 'code_issued')
  then
    raise exception 'expired enrollment code cannot complete pairing (target status=%, code_expires_at=%)',
      NEW.status, NEW.code_expires_at
      using errcode = '23514';
  end if;
  return NEW;
end;
$$;

comment on function app.enforce_pairing_code_expiry() is
  'RF-016 integrity guard: gates ONLY enrollment-completion edges (INSERT into a redeemed state, or code_issued -> pending/paired/active) — an expired code there is rejected (23514). Post-enrollment transitions (paired->active, suspended->active re-enable per STATE_MACHINES §9) are NOT gated. Not the authoritative pairing workflow (RF-050/RF-051).';

-- 6b. A PIN session may be ACTIVE only on an active, non-revoked device session
--     whose backing pairing is active. Inspects RLS-protected parent rows, so it
--     is a HARDENED SECURITY DEFINER (search_path locked, schema-qualified, no
--     caller-supplied flags, read-only, no privilege escalation). NOT granted to
--     app roles (trigger fires without an EXECUTE grant).
create or replace function app.enforce_pin_session_backing()
  returns trigger
  language plpgsql
  security definer
  set search_path = ''
as $$
declare
  v_ok boolean;
begin
  if NEW.is_active then
    select (ds.is_active and ds.revoked_at is null and dp.status = 'active')
      into v_ok
      from public.device_sessions ds
      join public.device_pairings dp on dp.id = ds.device_pairing_id
      where ds.id = NEW.device_session_id;

    if v_ok is not true then
      raise exception 'pin_session requires an ACTIVE, non-revoked device session backed by an ACTIVE pairing (device_session_id=%)',
        NEW.device_session_id
        using errcode = '23514';
    end if;
  end if;
  return NEW;
end;
$$;

comment on function app.enforce_pin_session_backing() is
  'RF-016 integrity guard: an active pin_session must sit on an active+non-revoked device_session whose pairing.status = active; else rejected (23514). Hardened SECURITY DEFINER (reads RLS-protected device_sessions/device_pairings; search_path locked). Not PIN workflow behavior (RF-051).';

-- Least privilege: these guard functions are trigger-only. Revoke the default
-- PUBLIC execute; do NOT grant to app roles (triggers run regardless).
revoke all on function app.enforce_pairing_code_expiry()  from public;
revoke all on function app.enforce_pin_session_backing()  from public;

-- ----------------------------------------------------------------------------
-- 7. Triggers: integrity guards + updated_at (reusing RF-014's app.set_updated_at).
-- ----------------------------------------------------------------------------
create trigger device_pairings_enforce_code_expiry
  before insert or update on device_pairings
  for each row execute function app.enforce_pairing_code_expiry();

create trigger pin_sessions_enforce_backing
  before insert or update on pin_sessions
  for each row execute function app.enforce_pin_session_backing();

create trigger devices_set_updated_at         before update on devices         for each row execute function app.set_updated_at();
create trigger device_pairings_set_updated_at before update on device_pairings for each row execute function app.set_updated_at();
create trigger device_sessions_set_updated_at before update on device_sessions for each row execute function app.set_updated_at();
create trigger pin_sessions_set_updated_at    before update on pin_sessions    for each row execute function app.set_updated_at();

-- ----------------------------------------------------------------------------
-- 8. RLS (DECISION D-012 L1). All four tables ENABLE + FORCE, deny-by-default,
--    reusing the RF-015 membership-derived resolver + scope predicate. Device-
--    as-RLS-principal is DEFERRED to RF-050 (no device GUCs added — A4); these
--    rows are MANAGED by humans under the membership/branch scope.
-- ----------------------------------------------------------------------------
alter table devices         enable row level security;
alter table devices         force  row level security;
alter table device_pairings enable row level security;
alter table device_pairings force  row level security;
alter table device_sessions enable row level security;
alter table device_sessions force  row level security;
alter table pin_sessions    enable row level security;
alter table pin_sessions    force  row level security;

create policy devices_scoped on devices
  for all to authenticated
  using      (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id))
  with check (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));

create policy device_pairings_scoped on device_pairings
  for all to authenticated
  using      (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id))
  with check (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));

create policy device_sessions_scoped on device_sessions
  for all to authenticated
  using      (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id))
  with check (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));

create policy pin_sessions_scoped on pin_sessions
  for all to authenticated
  using      (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id))
  with check (organization_id = app.current_org_id() and app.has_scope(organization_id, restaurant_id, branch_id));

-- ----------------------------------------------------------------------------
-- 9. Grants: least privilege, authenticated only (never anon).
-- ----------------------------------------------------------------------------
grant select, insert, update, delete on devices         to authenticated;
grant select, insert, update, delete on device_pairings to authenticated;
grant select, insert, update, delete on device_sessions to authenticated;
grant select, insert, update, delete on pin_sessions    to authenticated;

-- ============================================================================
-- DOWN (manual) — Supabase migrations are forward-only; cleanliness gate is
-- `supabase db reset`. Reverse-dependency teardown:
-- ----------------------------------------------------------------------------
-- drop table if exists pin_sessions;
-- drop table if exists device_sessions;
-- drop table if exists device_pairings;
-- drop table if exists devices;
-- drop function if exists app.enforce_pin_session_backing();
-- drop function if exists app.enforce_pairing_code_expiry();
-- alter table employee_profiles drop constraint if exists employee_profiles_org_id_key;
-- ============================================================================
