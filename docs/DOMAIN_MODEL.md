# DOMAIN_MODEL.md — RestoFlow Domain & Data Model

> **Status — DRAFT (candidate), not yet frozen.** Drafted by Claude Code (RF-001) · pending ChatGPT review · pending independent Codex review · pending human approval (Saleh). Only the explicit RF-001 invariants (below/where cited) are binding requirements; every other architectural choice is a **PROPOSED DECISION** pending review and human approval. Architecture freeze happens only after independent review, required fixes, and Saleh's approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

**Status:** DRAFT candidate for M0A (RF-001) — proposed for the architecture freeze, pending review and approval.
**Owner of this topic:** This document is the authoritative source of truth for **entities, fields, and relationships**. Other documents reference these entities; they do not redefine them.

This document **owns** the entity/field/relationship model. It does **not** own:
- Money/tax/receipt arithmetic and rounding — see [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md).
- Status transitions and lifecycle rules — see [STATE_MACHINES](STATE_MACHINES.md).
- Security/RLS/threat model and isolation tests — see [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md).
- Sync/outbox/inbox/conflict mechanics — see [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md).
- RPC/endpoint contracts — see [API_CONTRACT](API_CONTRACT.md).
- The decision log — see [DECISIONS](DECISIONS.md). The open-questions register — see [OPEN_QUESTIONS](OPEN_QUESTIONS.md).

Status column values in this document use **only** the PROPOSED enumerations defined in [STATE_MACHINES](STATE_MACHINES.md) (**DECISION D-018** — PROPOSED pending review and approval; RF-001 §8 directs us to evaluate, not assume final). No new states are invented here.

---

## 0. Foundational invariants (apply to every table below)

- **DECISION D-001** — `organization_id` is the **primary tenant-isolation boundary**. **Every tenant-scoped table carries `organization_id`** as a non-null foreign key. This is repeated explicitly per entity and is not optional anywhere.
- **DECISION D-003** — The **tenant is the Organization**, not the Restaurant. In the simplest pilot an Organization contains exactly one Restaurant and one Branch, but **no table, query, index, or constraint may assume a single restaurant/organization exists**. There is **no global-single-restaurant assumption** anywhere in this model.
- **DECISION D-002** — Hierarchy is `Platform -> Organization -> Restaurant -> Branch -> Device/Station`. Operational rows carry `restaurant_id`, `branch_id`, `device_id`, `station_id` **where relevant** (stated per entity), in addition to `organization_id`.
- **DECISION D-017 (naming)** — Tables are `snake_case`, plural. Primary key is a UUID column named `id`. Timestamps `created_at` / `updated_at`. Soft-delete tombstone `deleted_at` on sync-relevant tables (**DECISION D-020**). Money columns are **integers** suffixed `_minor` (**DECISION D-007**), accompanied by a currency code where standalone.
- **DECISION D-007 (money)** — All monetary amounts are stored as **integer minor units** (e.g. agorot/cents). **No floating point for money anywhere** — not in DB, RPC, Dart domain, or sync payloads. Money semantics, rounding, discounts, and tax computation are defined in [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md); this document only declares the columns.
- **DECISION D-008** — Orders capture **price and modifier snapshots at order time** and never recompute from live menu prices.
- **Standard sync columns (DECISION D-010, D-020, D-022)** — Tables that can be created or mutated offline carry the **standard sync column set**:
  - `device_id` (originating device, **D-022**)
  - `local_operation_id` (client-generated per-op id; `device_id + local_operation_id` = idempotency key, **D-022**)
  - `revision` (integer monotonic entity version)
  - `client_created_at`, `client_updated_at` (device clock)
  - `created_at`, `updated_at` (server clock)
  - `deleted_at` (tombstone, **D-020**)

  Per-entity sections say **"Sync: standard set"** when they carry all of the above, or list deviations. Reference tables that are only edited by privileged online roles (e.g. organizations, restaurants) may omit `local_operation_id`/`device_id`; this is noted per entity.
- **SECURITY REQUIREMENT** — No table stores service-role credentials, and no human-shared password column exists. Credential material (PIN, device secret) is stored only as a **reference/hash**, never plaintext (**DECISION D-004, D-006**, detailed in [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md)).

> **ASSUMPTION** — Field lists below are the proposed *minimum* contract (pending review and approval). M0B migrations may add non-breaking columns (indexes, denormalized caches) provided they do not violate the invariants above. Breaking changes require a new **DECISION** and a dedicated ticket per **DECISION D-016**.

---

## 1. Entity Relationship Overview (ASCII)

### 1.1 Tenant hierarchy (DECISION D-002, D-001, D-003)

```
                         +--------------+
                         |   Platform   |   (not a tenant row; platform_admin scope)
                         +------+-------+
                                | 1..*
                         +------v-------+
                         | organization |  <== TENANT BOUNDARY (organization_id, D-001)
                         +------+-------+
                                | 1..*
                         +------v-------+
                         |  restaurant  |  (restaurant_id)
                         +------+-------+
                                | 1..*
                         +------v-------+
                         |    branch    |  (branch_id)
                         +--+--------+--+
                            | 1..*   | 1..*
                   +--------v--+   +-v----------+
                   |  station  |   |   device   |  (station_id / device_id)
                   +-----------+   +------------+
```

Every box below the Organization line is a child of exactly one Organization and **carries `organization_id`** (D-001). `restaurant`/`branch`/`station`/`device` additionally carry the ids of their parents in the hierarchy.

### 1.2 Identity separation (DECISION D-004, D-005, D-006)

Six distinct concepts are kept structurally separate. **No shared accounts** (D-004).

> **Note (six identity concepts vs role keys):** The six distinct identity concepts are `app_user`, `membership`, `employee_profile`, `device`, `device_session`, and `pin_session`. The **six membership role keys** (`org_owner`, `restaurant_owner`, `manager`, `cashier`, `kitchen_staff`, `accountant`) are **VALUES on the `membership` concept** — they are not additional identity concepts. **`platform_admin` is NOT a membership role** (**DECISION D-026**): platform-level administrative access is modelled by the separate `platform_admin_grants` entity (§3.7), never as a tenant membership, and never carries `organization_id`.

```
   app_user (global person/auth principal — NOT tenant-scoped)
      |
      | 1..*  (a user may belong to many orgs)
      v
   membership (user x organization [+restaurant/+branch], carries role + scope)
      |
      |  org_owner | restaurant_owner | manager | cashier | kitchen_staff | accountant
      |  (six membership roles; platform_admin is NOT a membership role — modelled as
      |   platform_admin_grants (§3.7); never carries organization_id; separate audited path — D-026)
      v
   organization

   employee_profile  -- employment record WITHIN an organization (display name,
                        employee_number, PIN credential reference, employment status).
                        Linked to app_user (optional) but is NOT the user and NOT the membership.

   device            -- device identity (POS/KDS), NOT a human. Own credentials.
      |  1..*
      +-- device_pairing  (enrollment lifecycle: code_issued -> ... -> revoked)
      +-- device_session  (authenticated device session)
              |  1..*
              +-- pin_session  (short human PIN session layered on a device_session)
                       |
                       +-- references employee_profile (who) + device_session (where)
```

**Key separation rules:**
- `app_user` = WHO globally. `membership` = WHAT they may do and WHERE (scope + role). `employee_profile` = their employment record in one org. `device`/`device_session` = the machine. `pin_session` = a fast staff session on an already-paired+authorized device.
- A `cashier`/`kitchen_staff` authenticates by **PIN on a paired+authorized device** (`pin_session` on top of `device_session`) — they still have a personal `employee_profile` identity (D-006). Owners/managers use personal accounts with MFA where required (**OPEN QUESTION Q-008**).
- **Membership resolution rule (PROPOSED):** every PIN-capable `employee_profile` resolves to **exactly one** `membership` (carrying role + scope) within the SAME organization, by this precedence: **(1) authoritative** — the direct FK `employee_profiles.membership_id` when set. This is REQUIRED for any employee who may start a PIN session, because `app_user_id` is **nullable** (a cashier/kitchen_staff member need not hold a full account), so the indirect path cannot be relied upon. **(2) fallback** — when `membership_id` is null and `app_user_id` is set, resolve via `employee_profile -> app_user -> membership` **only if** that user has exactly one active membership in this `organization_id` (a user may legitimately hold several memberships across restaurants/branches in one org, so this path is used only when unambiguous). If neither path yields exactly one active membership, a PIN session **MUST NOT** be created until an explicit `membership_id` is assigned. A `pin_session` records the resolved membership (`resolved_membership_id`) so the session deterministically carries role + scope at creation time. Authorization enforcement remains owned by [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md).

### 1.3 Operational core (one branch's order flow)

```
 menu_category --< menu_item --< item_size
                       |   \--< item_variant
                       |    \--< modifier --< modifier_option
                       |
 table ---------\      |
                 v     v
              order --< order_item --< order_item_modifier
                 |          |
                 |          +--> kitchen_station_item >-- kitchen_ticket (per station)
                 |
                 +--< payment
                 +--> shift (operational period) --> cash_drawer_session
                 +..> print_job (receipt/ticket render)

 sync_operation  -- outbox/ledger for every mutating op (idempotency, D-022)
 audit_event     -- append-only audit of sensitive mutations (D-013)
```

`order_item` snapshots its source menu prices at order time (**D-008**). Each `order_item` may fan out to one or more `kitchen_station_item`s routed to stations; `kitchen_ticket` groups station items per station.

---

## 2. Tenant hierarchy entities

### 2.1 `organizations`
- **Purpose:** The tenant. Top of the customer hierarchy and the **isolation boundary** (D-001). A small restaurant = one organization; a restaurant group = one organization owning many restaurants (D-002, D-003).
- **Key fields:** `id` (UUID PK), `name`, `slug`, `default_currency` (ISO 4217 code — see **OPEN QUESTION Q-007** and [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md)), `country_code` (**OPEN QUESTION Q-001**, drives tax/fiscal config), `status` (`active`/`suspended` — **ASSUMPTION**, org lifecycle is not in the D-018 proposed set), `created_at`, `updated_at`, `deleted_at`.
- **Tenant/scoping:** This row **defines** `organization_id` (its own `id`); it is the root, so it does not reference a parent organization. **Note:** `organizations` is the **sole** table where `organization_id` is its own primary key (the root of the tenant tree) rather than a foreign key to a parent — every other tenant-scoped table carries `organization_id` as a non-null FK to `organizations.id` (D-001).
- **FKs:** none upward.
- **Money:** `default_currency` only (no `_minor` amounts here).
- **Sync:** privileged online edit; carries `created_at`/`updated_at`/`deleted_at`, omits `device_id`/`local_operation_id`. **SECURITY REQUIREMENT:** never readable across tenants (RLS, [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md)).

### 2.2 `restaurants`
- **Purpose:** A brand/concept within an organization. A group org may have Restaurant A and Restaurant B (D-002).
- **Key fields:** `id`, `name`, `currency_override` (nullable ISO 4217; overrides org currency — **Q-007**), `timezone`, `status` (`active`/`suspended` — **ASSUMPTION**, not in D-018 proposed set), timestamps + `deleted_at`.
- **Tenant/scoping:** `organization_id` (**D-001**, NOT NULL).
- **FKs:** `organization_id -> organizations.id`.
- **Sync:** privileged online edit (as organizations).

### 2.3 `branches`
- **Purpose:** A physical location/outlet of a restaurant. Receipt sequences and shifts are **per-branch** (D-021).
- **Key fields:** `id`, `name`, `address`, `timezone`, `receipt_prefix`, `status` (`active`/`suspended` — **ASSUMPTION**), timestamps + `deleted_at`.
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`.
- **FKs:** `organization_id -> organizations.id`, `restaurant_id -> restaurants.id`.
- **Notes:** The branch is the scope for the **per-branch monotonic receipt sequence** (D-021) — the sequence counter itself is described in [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md). `receipt_prefix` is a **display adornment** over the authoritative per-branch sequence (the human-facing receipt number format is gated by **OPEN QUESTION Q-004**); it is not the sequence itself.

### 2.4 `stations`
- **Purpose:** A logical kitchen/prep station (e.g. grill, bar, cold) used to route order items to KDS. **DECISION D-017** lists `stations` as a canonical table.
- **Key fields:** `id`, `name`, `type` (free/enum label, e.g. `kitchen`/`bar`), `display_order`, `is_active`, timestamps + `deleted_at`.
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`, `branch_id`.
- **FKs:** `organization_id`, `restaurant_id`, `branch_id` to their parents.
- **Used by:** `kitchen_ticket` and `kitchen_station_item` reference `station_id`; menu routing maps items to stations.

### 2.5 `devices`
- **Purpose:** A **device identity** (POS or KDS) with its own credentials and limited permissions — **not a human** (D-005, D-006).
- **Key fields:** `id`, `name`/`label`, `device_type` (`pos`/`kds` — **ASSUMPTION** label set; not in D-018), `device_credential_ref` (reference/hash only — **SECURITY REQUIREMENT**, no secrets in clients), `last_seen_at`, `is_active`, timestamps + `deleted_at`.
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`, `branch_id`. `device_id` elsewhere refers to `devices.id`.
- **FKs:** `organization_id`, `restaurant_id`, `branch_id`.
- **RISK R-007 / SECURITY REQUIREMENT:** revoking a device must remove **future** access including in the offline window (**OPEN QUESTION Q-009**); enforcement detail in [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) and [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md).

---

## 3. Identity & access entities (D-004, D-005, D-006)

### 3.1 `app_users`
- **Purpose:** The global person / auth principal (concept #1). **NOT tenant-scoped** — a user can belong to many organizations. **No shared accounts** (D-004).
- **Key fields:** `id` (UUID, aligns with the auth provider subject), `email`, `display_name`, `is_active`, `mfa_enabled` (**Q-008**), timestamps. (Auth credentials live in the auth provider, not here.)
- **Tenant/scoping:** **none** — deliberately global. Tenant linkage happens only through `memberships`.
- **FKs:** none to tenant tables (linkage is via membership).
- **SECURITY REQUIREMENT:** no password/PIN plaintext stored here.

### 3.2 `memberships`
- **Purpose:** A user's **scoped relationship** to an Organization carrying role(s) + scope (concept #2). Roles are **membership-scoped, never a permanent global role on the user** (D-004).
- **Key fields:** `id`, `role` (one of the **six PROPOSED tenant membership role keys**: `org_owner`, `restaurant_owner`, `manager`, `cashier`, `kitchen_staff`, `accountant` — accountant is **strictly read-only** (**DECISION D-028**), **OPEN QUESTION Q-017** on whether it ships in MVP; **`platform_admin` is NOT a membership role** and is excluded from this enum — **DECISION D-026**, see §3.7 `platform_admin_grants`), `status` (`active`/`revoked` — **ASSUMPTION**, not in D-018 proposed set; cross-ref threat **T-005**, do NOT freeze pending review), `permissions` (optional fine-grained overrides), timestamps + `deleted_at`.
- **Tenant/scoping:** `organization_id` (**D-001**, NOT NULL). Optional narrower scope: `restaurant_id` (nullable), `branch_id` (nullable). A null restaurant/branch means org-wide within the role.
- **FKs:** `app_user_id -> app_users.id`, `organization_id`, nullable `restaurant_id`, nullable `branch_id`.
- **Notes:** `platform_admin` is **NOT an organization membership** (**DECISION D-026**). Platform-level administrative access is now formalized as the separate `platform_admin_grants` entity (§3.7), which never carries `organization_id` and is reached only via a platform-level, separately audited path (D-012/D-013, [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md)). It does not grant tenant data access by itself. Authorization logic is owned by [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md); this table only declares the data.

### 3.3 `employee_profiles`
- **Purpose:** Employment record **within an organization** (concept #3): display name, employee number, PIN credential reference, employment status. Distinct from `app_user` and `membership`.
- **Key fields:** `id`, `employee_number`, `display_name`, `pin_credential_ref` (hash/reference only — **SECURITY REQUIREMENT**, never plaintext), `employment_status` (`active`/`suspended`/`terminated` — **ASSUMPTION**, not in D-018 proposed set; cross-ref threat **T-005**, do NOT freeze pending review), timestamps + `deleted_at`.
- **Tenant/scoping:** `organization_id` (**D-001**, NOT NULL); optionally `restaurant_id`/`branch_id` for the employee's home location (nullable).
- **FKs:** `organization_id`; nullable `app_user_id -> app_users.id` (an employee may also be a full account holder; cashier/kitchen staff still have a personal identity per D-006 but **need not** hold a full account); `membership_id -> memberships.id` (PROPOSED — the **authoritative** direct link to the membership that carries role + scope; nullable in general, but **REQUIRED for any PIN-capable profile** precisely because `app_user_id` may be null). When set it MUST reference a membership in the same `organization_id`.
- **Membership resolution (PROPOSED):** role + scope resolve by precedence (full rule in §1.2): **(1)** the direct `employee_profiles.membership_id` (authoritative); **(2)** only when that is null and `app_user_id` is set, via `employee_profile -> app_user -> membership` and only if the user has **exactly one** active membership in this `organization_id`. The resolved membership MUST share this profile's `organization_id`. If resolution is ambiguous or empty, no PIN session may be created until `membership_id` is assigned — so a singleton-membership constraint is **not** assumed. This is the deterministic path a `pin_session` uses to carry role + scope (see §3.6). Enforcement owned by [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md).
- **RISK R-007:** removing an employee must prevent **new valid operations**, including during the offline window (**Q-009**); enforcement in [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md).

### 3.4 `device_pairings`
- **Purpose:** Controlled enrollment lifecycle binding a `device` to a branch via a short-lived, expiring enrollment code (D-006).
- **Key fields:** `id`, `enrollment_code` (hash/reference), `code_expires_at`, `status`, `paired_at`, `revoked_at`, timestamps + `deleted_at`.
- **Status column (PROPOSED, D-018 — pending review and approval; RF-001 §8 directs evaluation, not final assumption — Device pairing):** `code_issued -> pending -> paired -> active -> suspended -> revoked`; plus `code_expired`, `rejected`. **Terminal:** `revoked`, `code_expired`, `rejected`. Transitions in [STATE_MACHINES](STATE_MACHINES.md).
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`, `branch_id`.
- **FKs:** `device_id -> devices.id`, `organization_id`, `restaurant_id`, `branch_id`.
- **SECURITY REQUIREMENT:** enrollment codes are short-lived/expiring; stored only as references.

### 3.5 `device_sessions`
- **Purpose:** An authenticated session bound to a **device identity** (concept #5).
- **Key fields:** `id`, `session_token_ref` (reference/hash only), `started_at`, `expires_at`, `revoked_at`, `is_active`, timestamps.
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`, `branch_id`.
- **FKs:** `device_id -> devices.id`, `device_pairing_id -> device_pairings.id` (the pairing that authorized it), plus hierarchy ids.
- **Notes:** A revoked device's sessions must be invalidated; reconnect rejects new ops (**RISK R-007**, **Q-009**).

### 3.6 `pin_sessions`
- **Purpose:** A short, fast **human PIN session** established by an employee's PIN on an already-paired+authorized device — layered on top of a `device_session` (concept #6, D-006).
- **Key fields:** `id`, `started_at`, `expires_at` (short-lived; offline validity governed by **OPEN QUESTION Q-009**), `ended_at`, `is_active`, `resolved_membership_id` (the membership resolved at session creation — see below), timestamps.
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`, `branch_id`.
- **FKs:** `device_session_id -> device_sessions.id`, `employee_profile_id -> employee_profiles.id`, `resolved_membership_id -> memberships.id` (the membership resolved by the §3.3 precedence — `employee_profiles.membership_id` first, else the unambiguous `app_user` membership — in the **same organization**, so the session deterministically carries role + scope), plus hierarchy ids.
- **Notes (PROPOSED):** `resolved_membership_id` is captured at session creation following the membership resolution rule (§3.3); it MUST reference a membership in the same `organization_id`, and session creation is **REFUSED if resolution is ambiguous or empty**. This makes a PIN session deterministically bound to a single role + scope without re-resolving per request.
- **SECURITY REQUIREMENT:** a PIN session is only valid on a paired+authorized device; PIN material is never stored here in plaintext.

### 3.7 `platform_admin_grants` (PROPOSED, **DECISION D-026**)
- **Purpose:** Records **platform-level administrative access** — the privilege held by Anthropic/RestoFlow platform operators to administer the platform itself. This is **NOT a tenant membership** (**D-026**): it is deliberately separate from `memberships` and from the six tenant membership roles, and it never grants tenant data access implicitly. `platform_admin` is therefore **not** a value of `memberships.role`.
- **Key fields:** `id` (UUID PK), `status` (PROPOSED lifecycle `active -> suspended -> revoked` — **ASSUMPTION** label set, not in the D-018 proposed set; pending review and approval), `granted_at`, `revoked_at`, `created_at`, `updated_at`.
- **Tenant/scoping:** **explicitly NONE** — this entity carries **NO `organization_id`** and **no `restaurant_id`/`branch_id`/`device_id`/`station_id`** scope. It is a platform-scoped grant by design (**D-026**); it sits outside the tenant hierarchy and the tenant-isolation boundary (D-001) does not apply to it.
- **FKs:** `app_user_id -> app_users.id` (the user identity that holds the grant); `granted_by -> app_users.id` (who issued the grant); `revoked_by -> app_users.id` (who revoked it, nullable until revoked). No FK to any tenant table.
- **Notes (PROPOSED, D-026):**
  - Accessed **only via a separate, privileged, explicitly-audited authorization path**, owned by [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md) — never the ordinary tenant authorization path.
  - **MFA required** for platform administrators (**OPEN QUESTION Q-008**).
  - **Every** platform-level access and mutation is audited as an `audit_event` (**DECISION D-013**), on the separate platform-admin audit path.
  - A platform-admin grant **never silently bypasses tenant protections** (RLS / membership scoping / RPC authorization remain in force; any cross-tenant platform action is explicit and audited).

---

## 4. Menu entities (D-008 snapshots downstream)

> Menu rows are editable offline by privileged staff and consumed during ordering. They carry the **standard sync set** so menu changes while offline are reconciled and price snapshots remain authoritative (**D-008**, [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md)).

### 4.1 `menu_categories`
- **Purpose:** Grouping of menu items for display/ordering.
- **Key fields:** `id`, `name` (localizable; ar/he/en per **D-014**), `display_order`, `is_active`, timestamps + `deleted_at`.
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`. (Menus are typically per-restaurant; `branch_id` nullable for branch-specific overrides — **ASSUMPTION**.)
- **FKs:** `organization_id`, `restaurant_id`.
- **Sync:** standard set.

### 4.2 `menu_items`
- **Purpose:** A sellable menu product.
- **Key fields:** `id`, `name` (localizable), `description`, `base_price_minor` (**integer minor units, D-007**), `currency` (ISO 4217; single currency per order enforced at order time — **Q-007**), `default_station_id` (routing to KDS), `is_active`, timestamps + `deleted_at`.
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`.
- **FKs:** `organization_id`, `restaurant_id`, `menu_category_id -> menu_categories.id`, nullable `default_station_id -> stations.id`.
- **Money:** `base_price_minor` (no floating point). Live price is **never** used after order placement (**D-008**); see `order_items` snapshot.
- **Sync:** standard set.

### 4.3 `item_sizes`
- **Purpose:** Size variants of a menu item (e.g. Small/Medium/Large) with a price delta or absolute price.
- **Key fields:** `id`, `name` (localizable), `price_delta_minor` **or** `price_minor` (**integer minor units, D-007**), `display_order`, `is_active`, timestamps + `deleted_at`.
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`.
- **FKs:** `menu_item_id -> menu_items.id`, `organization_id`, `restaurant_id`.
- **Money:** `_minor` integers only.

### 4.4 `item_variants`
- **Purpose:** Non-size variants of an item (e.g. flavor, preparation) that may adjust price.
- **Key fields:** `id`, `name` (localizable), `price_delta_minor` (**integer minor units, D-007**), `display_order`, `is_active`, timestamps + `deleted_at`.
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`.
- **FKs:** `menu_item_id -> menu_items.id`, `organization_id`, `restaurant_id`.

### 4.5 `modifiers`
- **Purpose:** A group of selectable options attached to a menu item (e.g. "Toppings", "Cooking level"), with selection rules.
- **Key fields:** `id`, `name` (localizable), `selection_type` (`single`/`multiple` — **ASSUMPTION**), `min_select`, `max_select`, `is_required`, `display_order`, `is_active`, timestamps + `deleted_at`.
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`.
- **FKs:** `menu_item_id -> menu_items.id` (or a many-to-many link table — **ASSUMPTION**, finalized in M0B), `organization_id`, `restaurant_id`.

### 4.6 `modifier_options`
- **Purpose:** An individual choice within a modifier (e.g. "Extra cheese") with a price.
- **Key fields:** `id`, `name` (localizable), `price_minor` (**integer minor units, D-007**), `display_order`, `is_active`, timestamps + `deleted_at`.
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`.
- **FKs:** `modifier_id -> modifiers.id`, `organization_id`, `restaurant_id`.
- **Money:** `price_minor` is snapshotted into `order_item_modifiers` at order time (**D-008**).

---

## 5. Floor entity

### 5.1 `tables`
- **Purpose:** A physical dining table (or seating spot) at a branch, for dine-in orders. (D-017 lists `tables` as canonical.)
- **Key fields:** `id`, `label`/`number`, `seats`, `area`/`zone`, `is_active`, timestamps + `deleted_at`.
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`, `branch_id`.
- **FKs:** `organization_id`, `restaurant_id`, `branch_id`.
- **Sync:** standard set (table layout can be edited offline — **ASSUMPTION**).

---

## 6. Order entities

### 6.1 `orders`
- **Purpose:** A customer order (dine-in/takeaway). Created at a POS, possibly offline; reconciled on sync. Receipt number is a per-branch server-assigned monotonic sequence (D-021).
- **Key fields:** `id`, `order_type` (`dine_in`/`takeaway` — **ASSUMPTION** label set; takeaway skips `served` per D-018), `receipt_number` (authoritative, server-assigned), `receipt_provisional_id` (offline provisional, reconciled on sync — **D-021**), `currency` (ISO 4217; **single currency per order**, **Q-007**), `subtotal_minor`, `discount_total_minor`, `tax_total_minor`, `grand_total_minor` (**all integer minor units, D-007**; computation owned by [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md)), `void_reason` (when voided), timestamps + `deleted_at`.
- **Status column (PROPOSED, D-018 — pending review and approval; RF-001 §8 directs evaluation, not final assumption — Order):** `draft -> submitted -> accepted -> preparing -> ready -> served -> completed`; plus `cancelled` (pre-production, terminal) and `voided` (post-submission, requires authorization + reason, terminal). **Takeaway:** `ready -> completed` (skips `served`). **Terminal:** `completed`, `cancelled`, `voided`. **DECISION D-024:** `completed` is **TERMINAL** — `completed -> voided` and `completed -> cancelled` are **FORBIDDEN**. A **pre-completion** cancel/void is **rejected if a completed payment exists** on the order (the appropriate remedy would be a refund, which is **DEFERRED**). Transitions in [STATE_MACHINES](STATE_MACHINES.md).
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`, `branch_id`, `device_id` (originating), `station_id` not applicable at order level.
- **FKs:** hierarchy ids; nullable `table_id -> tables.id` (dine-in); `shift_id -> shifts.id`; `opened_by_employee_profile_id -> employee_profiles.id`.
- **Money:** all amounts `_minor`. Order never recomputes from live menu (**D-008**); arithmetic rules in [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md).
- **Payment/fulfillment independence (DECISION D-025):** payment and fulfillment are **independent** — **pay-first is supported**. Payment may **start** while the order is in `submitted`, `accepted`, `preparing`, `ready`, or `served` (the eligible payment-start states; `draft`, `cancelled`, `voided`, and `completed` are excluded). **Payment completion does NOT advance fulfillment** — completing a payment never moves the order along its fulfillment states (`preparing`/`ready`/`served`/`completed`); fulfillment transitions remain driven by their own actions. Lifecycle owned by [STATE_MACHINES](STATE_MACHINES.md).
- **Sync:** standard set. Idempotency key `device_id + local_operation_id` (**D-022**). **RISK R-002:** duplicate-order prevention via idempotency ([OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md)).

### 6.2 `order_items`
- **Purpose:** A line item on an order, with **price snapshots captured at order time** (D-008).
- **Key fields:** `id`, `quantity`, `menu_item_id` (reference), `menu_item_name_snapshot` (localizable display snapshot), `unit_price_minor_snapshot` (**integer minor units; snapshot, D-008**), `item_size_snapshot`/`item_variant_snapshot` (denormalized chosen size/variant + their price deltas, `_minor`), `line_discount_minor`, `line_total_minor` (**all `_minor`, D-007**), `void_reason` (when voided), timestamps + `deleted_at`.
- **Status column (PROPOSED, D-018 — pending review and approval; RF-001 §8 directs evaluation, not final assumption — Order item):** `pending -> queued -> preparing -> ready -> served`; plus `voided`, `cancelled` (terminal). Transitions in [STATE_MACHINES](STATE_MACHINES.md).
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`, `branch_id`. (Inherits order scope.)
- **FKs:** `order_id -> orders.id`, `menu_item_id -> menu_items.id` (reference only; price comes from snapshot), `organization_id`, `restaurant_id`, `branch_id`, nullable `station_id -> stations.id` (routing).
- **Money:** **snapshot** prices in `_minor`; never recomputed from live menu (**D-008**).
- **Sync:** standard set.

### 6.3 `order_item_modifiers`
- **Purpose:** A selected modifier option on an order item, with its **price snapshot at order time** (D-008).
- **Key fields:** `id`, `modifier_option_id` (reference), `modifier_name_snapshot`, `option_name_snapshot` (localizable), `price_minor_snapshot` (**integer minor units; snapshot, D-008**), `quantity`, timestamps + `deleted_at`.
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`, `branch_id`.
- **FKs:** `order_item_id -> order_items.id`, `modifier_option_id -> modifier_options.id` (reference), hierarchy ids.
- **Money:** `price_minor_snapshot` only.
- **Sync:** standard set.

---

## 7. Kitchen entities

### 7.1 `kitchen_tickets`
- **Purpose:** A station's view/grouping of items to prepare for an order; the unit the KDS acknowledges and bumps.
- **Key fields:** `id`, `ticket_number` (display), `recall_count`, `acknowledged_at`, `bumped_at`, timestamps + `deleted_at`.
- **Status column (PROPOSED, D-018 — pending review and approval; RF-001 §8 directs evaluation, not final assumption — Kitchen ticket):** `new -> acknowledged -> in_preparation -> ready -> bumped`; plus `recalled` and `cancelled`. **Note:** `recalled` is a **transition/audit marker** (the `bumped -> in_preparation` recall), not a distinct resting state — the resting state after a recall is `in_preparation` (per [STATE_MACHINES](STATE_MACHINES.md) §3). **Terminal:** `bumped`, `cancelled`. Transitions in [STATE_MACHINES](STATE_MACHINES.md).
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`, `branch_id`, `station_id`.
- **FKs:** `order_id -> orders.id`, `station_id -> stations.id`, hierarchy ids.
- **SECURITY REQUIREMENT:** KDS scope must not read financial reports (isolation test, [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md)).
- **Sync:** standard set.

### 7.2 `kitchen_station_items`
- **Purpose:** The per-station preparation state of an individual order item routed to a station.
- **Key fields:** `id`, `quantity`, `started_at`, `ready_at`, `bumped_at`, `void_reason`, timestamps + `deleted_at`.
- **Status column (PROPOSED, D-018 — pending review and approval; RF-001 §8 directs evaluation, not final assumption — Kitchen station item):** `queued -> in_preparation -> ready -> bumped`; plus `voided`. **Terminal:** `bumped`, `voided`. Transitions in [STATE_MACHINES](STATE_MACHINES.md).
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`, `branch_id`, `station_id`.
- **FKs:** `kitchen_ticket_id -> kitchen_tickets.id`, `order_item_id -> order_items.id`, `station_id -> stations.id`, hierarchy ids.
- **Sync:** standard set.

---

## 8. Payment & financial-period entities

### 8.1 `payments`
- **Purpose:** A tender against an order. Void vs cancellation vs refund are distinct ([MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md); refunds **DEFERRED**).
- **Key fields:** `id`, `method` (`cash`/`card`/... — **ASSUMPTION** label set), `amount_minor`, `tendered_minor`, `change_minor` (**all integer minor units, D-007**), `currency` (ISO 4217; matches order currency — **Q-007**), `void_reason`, timestamps + `deleted_at`.
- **Status column (PROPOSED, D-018 — pending review and approval; RF-001 §8 directs evaluation, not final assumption — Payment):** `pending -> tendered -> completed`; plus `voided`, `failed`. **`refunded` is DEFERRED.** **Terminal:** `completed`, `voided`, `failed`. **DECISION D-023:** `completed` is **TERMINAL** — `completed -> voided` is **FORBIDDEN**. Payment **void is only permitted pre-completion** (`pending -> voided`, `tendered -> voided`); refunds/reversals are **DEFERRED**. Transitions in [STATE_MACHINES](STATE_MACHINES.md).
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`, `branch_id`, `device_id`.
- **FKs:** `order_id -> orders.id`, `shift_id -> shifts.id`, `cash_drawer_session_id -> cash_drawer_sessions.id` (for cash), `taken_by_employee_profile_id -> employee_profiles.id`, hierarchy ids.
- **Money:** all `_minor`. **DEFERRED:** tips (**Q-011**); service charge rules (**Q-012**).
- **Sync:** standard set. **RISK R-002:** payment-duplication prevention via idempotency `device_id + local_operation_id` (**D-022**, [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md)).
- **SECURITY REQUIREMENT:** voiding a paid order/payment requires permission (isolation test: a cashier cannot void a paid order without permission — [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md)); enforced via RPC (**D-011**) and audited (**D-013**).

### 8.2 `shifts`
- **Purpose:** An operational work period at a branch, the rollup boundary for sales/cash reporting.
- **Key fields:** `id`, `opened_at`, `closed_at`, `reconciled_at`, `expected_total_minor`, `counted_total_minor`, `variance_minor` (**all integer minor units, D-007**), timestamps + `deleted_at`.
- **Money cross-ref:** `expected_total_minor` here is what [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md) calls `expected_cash_minor`; the signed variance definition (`variance_minor = counted - expected`) is **owned** by [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md) — this document only declares the column.
- **Status column (PROPOSED, D-018 — pending review and approval; RF-001 §8 directs evaluation, not final assumption — Shift):** `opening -> open -> closing -> closed -> reconciled`. **Terminal:** `reconciled`. Transitions in [STATE_MACHINES](STATE_MACHINES.md).
- **Close/count vs reconciliation (DECISION D-028):** **shift close/count** (`close_shift`; performed by the cashier or an authorized manager) and **reconciliation** (`reconcile_shift`; performed by manager / restaurant_owner / org_owner) are **separate** operations with separate authorization. The `accountant` role is **strictly read-only** and performs **no mutation** here (no close, no count, no reconcile). The `variance_minor = counted − expected` arithmetic is **owned** by [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md).
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`, `branch_id`.
- **FKs:** `opened_by_employee_profile_id -> employee_profiles.id`, hierarchy ids.
- **Money:** all `_minor`.
- **Sync:** standard set.

### 8.3 `cash_drawer_sessions`
- **Purpose:** A cash-drawer accounting session **bound to a shift** (opening float -> active -> counting -> closed with variance -> reconciled).
- **Key fields:** `id`, `opening_float_minor`, `counted_total_minor`, `expected_total_minor`, `variance_minor` (**all integer minor units, D-007**), `opened_at`, `closed_at`, `reconciled_at`, timestamps + `deleted_at`.
- **Money cross-ref:** `expected_total_minor` here is what [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md) calls `expected_cash_minor`; the signed variance definition (`variance_minor = counted - expected`) is **owned** by [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md) — this document only declares the column.
- **Status column (PROPOSED, D-018 — pending review and approval; RF-001 §8 directs evaluation, not final assumption — Cash drawer session):** `opened (opening float) -> active -> counting -> closed (counted+variance) -> reconciled`. **Terminal:** `reconciled`. **Bound to a shift.** Transitions in [STATE_MACHINES](STATE_MACHINES.md).
- **Close/count vs reconciliation (DECISION D-028):** the **close/count** step (`close_shift`; cashier or authorized manager) and the **reconciliation** step (`reconcile_shift`; manager / restaurant_owner / org_owner) are **separate** with separate authorization. The `accountant` role is **strictly read-only** and performs **no mutation** on the drawer session. `variance_minor = counted − expected` arithmetic is **owned** by [MONEY_AND_TAX_SPEC](MONEY_AND_TAX_SPEC.md).
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`, `branch_id`, `device_id` (the drawer's POS).
- **FKs:** `shift_id -> shifts.id` (NOT NULL — bound to a shift), `device_id -> devices.id`, `opened_by_employee_profile_id -> employee_profiles.id`, hierarchy ids.
- **Money:** all `_minor`.
- **Sync:** standard set.

---

## 9. Printing entity

### 9.1 `print_jobs`
- **Purpose:** A queued render of a receipt or kitchen ticket sent to an ESC/POS printer behind a replaceable adapter (D-009). Printing/encoding detail owned by [PRINTERS_AND_HARDWARE_SPEC](PRINTERS_AND_HARDWARE_SPEC.md).
- **Key fields:** `id`, `job_type` (`receipt`/`kitchen_ticket` — **ASSUMPTION** label set), `payload_ref` (rendered content/reference), `retry_count`, `max_retries`, `last_error`, `abandoned_at`, timestamps + `deleted_at`.
- **Status column (PROPOSED, D-018 — pending review and approval; RF-001 §8 directs evaluation, not final assumption — Print job):** `created -> queued -> printing -> printed`; plus `failed -> retrying`, `cancelled`, `abandoned` (after max retries). **Terminal:** `printed`, `cancelled`, `abandoned`. Transitions in [STATE_MACHINES](STATE_MACHINES.md).
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`, `branch_id`, `device_id` (printing device), nullable `station_id` (for kitchen tickets).
- **FKs:** nullable `order_id -> orders.id`, nullable `kitchen_ticket_id -> kitchen_tickets.id`, hierarchy ids.
- **RISK R-001 / R-006:** ESC/POS hardware variation and Arabic/Hebrew encoding (raster fallback) — **OPEN QUESTION Q-015**; handled in [PRINTERS_AND_HARDWARE_SPEC](PRINTERS_AND_HARDWARE_SPEC.md).
- **Sync:** standard set (jobs can be created offline).

---

## 10. Sync & audit entities

### 10.1 `sync_operations`
- **Purpose:** The **outbox/inbox/processed-operation ledger** entry for every mutating client operation (D-010, D-022). Owns the idempotency record; mechanics owned by [OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md).
- **Key fields:** `id`, `device_id`, `local_operation_id` (together the **idempotency key**, **D-022**), `operation_type`, `target_entity`, `target_id`, `payload` (op body), `client_created_at`, `server_received_at`, `applied_at`, `retry_count`, `conflict_info`, `rejection_reason`, timestamps.
- **Status column (PROPOSED, D-018 — pending review and approval; RF-001 §8 directs evaluation, not final assumption — Sync operation):** `created -> pending -> in_flight -> applied`; plus `rejected` (permanent), `dead` (poison after max retries), `conflict -> resolved`. **Terminal:** `applied`, `rejected`, `dead`. Transitions in [STATE_MACHINES](STATE_MACHINES.md).
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`, `branch_id`, `device_id`.
- **FKs:** `device_id -> devices.id`, hierarchy ids; `target_id` is a soft reference to the affected row.
- **Constraint:** **UNIQUE(`device_id`, `local_operation_id`)** enforces idempotency at the DB layer (**D-022**, layer 4 of **D-012**).
- **RISK R-002 / R-007:** duplicate-mutation handling, poison-operation handling, and rejection of ops from revoked devices/employees on reconnect ([OFFLINE_SYNC_SPEC](OFFLINE_SYNC_SPEC.md), **Q-009**, **Q-010**).

### 10.2 `audit_events`
- **Purpose:** Append-only audit of sensitive mutations (D-013). Captures full context. **Never updatable/deletable by app roles.**
- **Key fields (per D-013):** `id`, `actor` (`actor_app_user_id` and/or `actor_employee_profile_id`), `device_id`, `organization_id`, `restaurant_id`, `branch_id`, `timestamp` (`occurred_at`), `action`, `reason`, `old_values`, `new_values`, plus `created_at`.
- **Tenant/scoping:** `organization_id` (**D-001**), `restaurant_id`, `branch_id`, `device_id`.
- **FKs:** soft references to actor/device/hierarchy (kept resilient so audit survives deletes).
- **SECURITY REQUIREMENT:** append-only; no UPDATE/DELETE by application roles (enforced via RLS + DB constraints, **D-012/D-013**, [SECURITY_AND_THREAT_MODEL](SECURITY_AND_THREAT_MODEL.md)). Platform-admin actions are audited on a separate, explicit path. This table is **not** soft-deleted (no `deleted_at`) — it is permanent.
- **Note:** Audit is written by **SECURITY DEFINER RPC** at the same time as the sensitive mutation it records (**D-011**, [API_CONTRACT](API_CONTRACT.md)).

---

## 11. Cross-cutting summary

| Concern | Rule | Decision |
|---|---|---|
| Tenant isolation | `organization_id` NOT NULL on every tenant-scoped table | D-001 |
| No single-tenant assumption | No table/query assumes one org/restaurant | D-003 |
| Hierarchy ids | `restaurant_id`/`branch_id`/`device_id`/`station_id` where relevant | D-002 |
| Money | integer `_minor` columns; no floating point anywhere | D-007 |
| Price snapshots | order/order_item/modifier snapshots at order time | D-008 |
| Idempotency | `device_id + local_operation_id` UNIQUE on mutating ops | D-022 |
| Receipt numbering | per-branch monotonic server-assigned sequence + provisional | D-021 |
| Tombstones | `deleted_at` soft delete on sync-relevant tables | D-020 |
| Statuses | only PROPOSED D-018 enumerations (pending review/approval; RF-001 §8 directs evaluation); transitions in STATE_MACHINES | D-018 |
| Identity separation | user / membership / employee_profile / device / device_session / pin_session distinct | D-005 |
| Audit | append-only, full context, never editable by app roles | D-013 |
| Naming | snake_case plural tables, UUID `id`, `_minor` money | D-017 |

**Open questions touching this model** (a subset of the **Q-001..Q-024** register; see [OPEN_QUESTIONS](OPEN_QUESTIONS.md) for the full set and status): Q-001 (jurisdiction -> tax/fiscal fields), Q-007 (currency single/multi), Q-008 (MFA roles — including platform-admin MFA for `platform_admin_grants`, §3.7, D-026), Q-009 (offline auth validity), Q-010 (conflict policy per entity), Q-011 (tips — DEFERRED), Q-012 (service charge), Q-015 (printing encoding), Q-017 (accountant role in MVP). See [OPEN_QUESTIONS](OPEN_QUESTIONS.md).

**Risks touching this model:** R-002 (sync duplicates), R-003 (RLS cross-tenant leak — CRITICAL), R-007 (offline auth staleness), R-001/R-006 (printing). See [DECISIONS](DECISIONS.md) and the risk register.
