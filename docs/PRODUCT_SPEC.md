# RestoFlow — Product Specification (PRODUCT_SPEC.md)

> **Status — FROZEN: M0A architecture baseline, approved at RF-004.** Authored under RF-001, independently reviewed by Codex (RF-002), corrected under RF-003, and verified in a final Codex pass; the architecture freeze was **approved by the human owner, Saleh, at RF-004**. The explicit RF-001 invariants remain binding; decisions **D-001..D-028** are the frozen M0A baseline. Open questions **Q-001..Q-024** remain **Accepted Open** (per **DECISION D-027** — tracked, gating only their dependent tickets; none resolved or guessed). Changes to this frozen baseline now require the architecture-change procedure (a new ticket, independent review, and human approval). Any remaining inline pre-freeze status notes are superseded by this RF-004 approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

**Status:** M0A architecture-baseline document set, frozen as the M0A architecture baseline at RF-004 (approved into the frozen M0A baseline (RF-004)) (ticket RF-001).
**Owner of this document:** Product vision, personas, and product surfaces.
**Authority:** This document owns the product vision, target customers/personas, and the description of the product surfaces and core user journeys. It does NOT define money/tax, state transitions, security/RLS, sync, printing, API contracts, scope boundaries, or the decision/question registers — those belong to their owning documents and are referenced here, never redefined.

> Reading guide: Wherever a topic is owned by another document, this spec links to it instead of restating the rules. Markers (**DECISION**, **ASSUMPTION**, **OPEN QUESTION**, **DEFERRED**, **RISK**, **SECURITY REQUIREMENT**) cite the canonical IDs from [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

---

## 1. Vision

RestoFlow is a **multi-tenant Restaurant Operating System (Restaurant OS)** — not merely a point-of-sale application. It is the operational backbone that connects every surface a restaurant business uses to run service: cashier-facing POS stations, Kitchen Display Systems (KDS), owner/manager dashboards, and platform-level administration, with first-class support for offline operation, synchronization, printing, payments, shifts, and reporting.

RestoFlow is delivered as **Software-as-a-Service that serves many independent restaurant customers on one platform**. Each customer is an independent business with its own data, staff, menus, devices, and money — strictly isolated from every other customer.

The first pilot (milestone M3) will run with **one restaurant and one branch**, but this is a deployment fact, NOT an architectural assumption. **No part of the product — schema, API, authorization policy, local database, or app architecture — may assume that only one restaurant or one organization exists.**

- **DECISION D-001** — The primary tenant-isolation boundary is `organization_id`. Every tenant-scoped record is owned by an organization.
- **DECISION D-002** — The tenant hierarchy is `Platform -> Organization -> Restaurant -> Branch -> Device/Station`.
- **DECISION D-003** — The **tenant is the Organization** (this supersedes any earlier "Restaurant = Tenant" framing). In the simplest case an Organization contains exactly one Restaurant and one Branch; the model must never regress to restaurant-as-tenant.

### 1.1 What RestoFlow is

- A system of record for orders, payments, shifts, and the operational state of a restaurant business.
- An **offline-first** product: the POS keeps working with no internet, and reconciles authoritatively on reconnect. See [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md).
- A **multi-surface** product where POS, KDS, dashboards, and platform admin are coordinated views over the same governed data.
- A **localized** product: Arabic, Hebrew, and English, with full RTL and LTR support (**DECISION D-014**).

### 1.2 What RestoFlow is not (at the product level)

- It is not a single-restaurant desktop till. Single-tenant assumptions are prohibited.
- It is not a marketing site, a marketplace, or a delivery aggregator.
- The authoritative MVP exclusions live in [MVP_SCOPE.md](MVP_SCOPE.md); see §7 below.

### 1.3 Guiding product principles

1. **Tenant isolation is sacred.** A customer can never see, touch, or infer another customer's data. **RISK R-003** (an RLS bug leaking cross-tenant data) is treated as CRITICAL; isolation is validated by mandatory tests owned by [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md).
2. **Service never stops.** Loss of connectivity degrades cleanly to local operation, not failure.
3. **Every action is attributable.** No shared accounts; each human acts under an individual identity (**DECISION D-004**). Sensitive actions are audited (**DECISION D-013**).
4. **Money is exact.** All money is integer minor units; no floating point anywhere (**DECISION D-007**, owned by [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md)).
5. **Freeze before code.** The documentation set is authored as the candidate set frozen as the M0A architecture baseline at RF-004 before implementation; the freeze occurs only after independent review and human approval (**DECISION D-019**, milestone M0A).

---

## 2. Target customers & personas

### 2.1 Target customers

RestoFlow targets independent restaurant businesses and restaurant groups that need reliable in-venue operations.

- **Independent restaurant** — A business that maps to one Organization owning one Restaurant with one (or a few) Branches.
- **Restaurant group** — A business where one Organization owns multiple Restaurants (e.g. Restaurant A and Restaurant B), each with one or many Branches. This is a core supported shape per **DECISION D-002**, not a future enhancement.

- **ASSUMPTION** — Initial customers are quick-service and casual dine-in venues (dine-in and takeaway). Fine-dining table-management depth, coursing, and reservations are not assumed in scope; the authoritative in/out list is [MVP_SCOPE.md](MVP_SCOPE.md).

### 2.2 Personas

Tenant personas correspond to the membership-scoped role keys defined in the canon. Roles are **membership-scoped, never a permanent global role on the user** (**DECISION D-004**); a person may hold different roles in different organizations/restaurants/branches via memberships (**DECISION D-005**). The tenant role keys are exactly `org_owner`, `restaurant_owner`, `manager`, `cashier`, `kitchen_staff`, and `accountant` (read-only). **DECISION D-026** — `platform_admin` is **NOT** a tenant membership role; platform administration is a separate privileged grant (see §2.3), not an organization membership. Authoritative role/permission semantics are owned by [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md).

| Persona | Role key | Typical scope | Primary surfaces | What they need |
| --- | --- | --- | --- | --- |
| Organization owner | `org_owner` | Organization | Owner/manager dashboard | Cross-restaurant visibility, staff/device governance, money outcomes across the whole business |
| Restaurant owner | `restaurant_owner` | A restaurant (one or more branches) | Owner/manager dashboard | Per-restaurant performance, menu and staff oversight, branch-level reporting |
| Manager | `manager` | Branch (or restaurant) | Dashboard + POS | Open/close shifts, authorize voids/discounts, monitor service, reconcile cash, daily reports |
| Cashier | `cashier` | Branch + paired device | POS station | Fast, reliable order building, payment, change, receipts; works offline |
| Kitchen staff | `kitchen_staff` | Branch + station | KDS | See tickets, prepare, mark ready, bump; never sees financials |
| Accountant (read-only) | `accountant` | Organization/restaurant (read-only) | Dashboard (reports) | Read financial/operational reports; no mutations. **OPEN QUESTION Q-017** — whether this role ships in MVP or later. |

Identity, membership, employee profile, device identity, device session, and human PIN session are six distinct concepts (**DECISION D-005**); this spec uses the personas above and defers their precise authentication and authorization to [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md).

### 2.3 Platform administrator (not a tenant role)

The platform operator is **not** a tenant persona and holds **no** organization membership. **DECISION D-026** — platform administration is a separate, privileged, explicitly audited grant (`platform_admin_grants`, owned by [DOMAIN_MODEL.md](DOMAIN_MODEL.md) §3.7) with **no** `organization_id`; it is MFA-gated and audited on its own path. A platform administrator onboards/suspends tenants and supports the platform; this access never flows through tenant membership or tenant client surfaces (**DECISION D-012/D-013**). **OPEN QUESTION Q-008** — MFA method for privileged/platform access is unresolved.

- **SECURITY REQUIREMENT** — There are no shared accounts and no shared restaurant password; every human has an individual identity, and Flutter clients never hold service-role credentials (**DECISION D-004**, **DECISION D-011**).
- **OPEN QUESTION Q-008** — MFA method and which roles/grants must use it (privileged/sensitive roles and the separate platform-admin grant per §2.3) is unresolved; this spec flags privileged access without freezing the mechanism.

---

## 3. The product surfaces

RestoFlow is composed of coordinated surfaces over the same governed, tenant-isolated data. System structure and how these surfaces are built is owned by [ARCHITECTURE.md](ARCHITECTURE.md); this section describes them from a product standpoint.

### 3.1 POS station (cashier)

The cashier-facing surface running on a paired, authorized device.

- Build orders for **dine-in** and **takeaway**; apply item-level and order-level discounts (authorization rules referenced, not defined, here).
- Submit orders, route to kitchen, take **cash payment and compute change**, and trigger printing of kitchen tickets and customer receipts.
- Operate fully offline with a visible sync status, then reconcile on reconnect.
- A fast **human PIN session** is established on an already-paired and authorized device (**DECISION D-005/D-006**); the device itself has its own device identity and session.
- **SECURITY REQUIREMENT** — Cashiers and kitchen staff use a personal employee identity with a PIN-based fast session ONLY on a paired+authorized device (**DECISION D-006**).

### 3.2 Kitchen Display System (KDS)

The kitchen-facing surface, scoped to a branch and station.

- Displays kitchen tickets and station items, supports acknowledge / in-preparation / ready / bump, and audited recall.
- **SECURITY REQUIREMENT** — KDS must never expose financial reports or payment data (this is part of the canonical isolation test set in [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md)).
- Ticket and station-item lifecycles use the PROPOSED state enumerations (approved into the frozen M0A baseline (RF-004); RF-001 §8 directs us to evaluate, not assume final) owned by [STATE_MACHINES.md](STATE_MACHINES.md); this spec does not restate transitions.

### 3.3 Owner/manager dashboard

The management surface for owners, restaurant owners, managers, and (read-only) accountants.

- Visibility scoped by membership: an `org_owner` sees across restaurants/branches; a `manager` sees their branch.
- Provides shift status, cash reconciliation outcomes, and **daily reports** (report definitions referenced from the reporting capability and [MVP_SCOPE.md](MVP_SCOPE.md)).
- Surfaces staff/device governance entry points (employee membership and device pairing/revocation), with the authoritative model in [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md).

### 3.4 Platform administration

The platform-operator surface, strictly separate from tenant surfaces.

- Tenant onboarding, suspension, and support across organizations.
- **SECURITY REQUIREMENT** — Platform-admin access is a separate, explicitly audited path and must be isolated from tenant data flows (**DECISION D-012/D-013**); platform-admin actions are part of the mandatory isolation/audit tests.
- **DEFERRED** — Self-serve signup, billing, and full platform-admin tooling are M4 concerns (**OPEN QUESTION Q-016** for the billing model); see [MVP_SCOPE.md](MVP_SCOPE.md) and [PROJECT_PLAN.md](PROJECT_PLAN.md).

### 3.5 Supporting capabilities (cross-cutting)

These capabilities are surfaced inside POS/KDS/dashboard rather than being standalone screens; each is owned by a dedicated spec.

- **Offline operation & sync** — local SQLite/Drift store, outbox/inbox, idempotency, reconciliation; owned by [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md) (**DECISION D-010/D-020/D-022**). **RISK R-002**, **RISK R-007**.
- **Printing** — kitchen tickets and customer receipts via an ESC/POS adapter; owned by [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md). **RISK R-001**, **RISK R-006**. **OPEN QUESTION Q-015**.
- **Payments** — cash at MVP, with change calculation; money rules owned by [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md). Tips are **DEFERRED** (**OPEN QUESTION Q-011**).
- **Shifts & cash drawer** — open/close shifts and cash-drawer sessions with reconciliation; lifecycles owned by [STATE_MACHINES.md](STATE_MACHINES.md).
- **Reporting** — daily reports and operational/financial summaries scoped by membership; report scope is constrained by [MVP_SCOPE.md](MVP_SCOPE.md).

---

## 4. Core user journeys

These narratives describe product behavior. Status values referenced are the PROPOSED state enumerations (approved into the frozen M0A baseline (RF-004); RF-001 §8 directs us to evaluate, not assume final) owned by [STATE_MACHINES.md](STATE_MACHINES.md); money behavior is owned by [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md); authorization is owned by [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md). This spec never restates those rules — it shows how a persona experiences them.

### 4.1 Open a shift

1. Manager or cashier authenticates with a PIN session on a paired, authorized device.
2. A shift is opened (`opening -> open`) and a bound cash-drawer session is opened with an opening float (`opened -> active`).
3. The POS shows the station as ready for service and surfaces sync status.

### 4.2 Build and submit an order (dine-in and takeaway)

1. Cashier starts an order in `draft`, selecting an order type of dine-in or takeaway.
2. Items, sizes, variants, and modifiers are added; **item and modifier prices are snapshotted at order time** so the order never recomputes from live menu prices (**DECISION D-008**).
3. Discounts may be applied at item or order level subject to authorization.
4. The cashier submits the order (`draft -> submitted`); the order then progresses through acceptance and production states.
5. Takeaway orders follow the **same** lifecycle as dine-in — `ready -> served -> completed` — with `served` meaning the customer **picked the order up** (displayed "Picked up"; review B3), per [STATE_MACHINES.md](STATE_MACHINES.md).
6. **DECISION D-025** — Payment and fulfillment are **independent**. Quick-service **pay-first** is supported: cash payment may be taken as soon as the order is submitted/accepted (and during preparing/ready/served) — it does **not** require the food to be ready or served first, and completing payment does **not** imply the food is prepared/ready/served or the order completed.

### 4.3 Route to kitchen

1. On submission, the order produces kitchen tickets and station items routed to the relevant station(s).
2. Tickets appear on the KDS as `new`, ready to be acknowledged.

### 4.4 Prepare and bump

1. Kitchen staff acknowledge a ticket (`new -> acknowledged`), begin preparation (`-> in_preparation`), mark it ready (`-> ready`), and bump it (`-> bumped`).
2. A bumped ticket may be recalled to `in_preparation` (audited) when needed.
3. Corresponding order items advance through their own lifecycle toward `served`/`completed`.

### 4.5 Print kitchen ticket and customer receipt

1. On submission, a kitchen-ticket print job is created and flows through the print lifecycle (`created -> queued -> printing -> printed`), with retry/abandon handling.
2. At payment, a customer receipt is printed; the receipt carries a **per-branch monotonic server-assigned receipt number**, with an offline provisional id reconciled to the authoritative number on sync (**DECISION D-021**).
3. Localized receipts/tickets honor ar/he/en and RTL/LTR; Arabic/Hebrew encoding/raster fallback is owned by [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md). **OPEN QUESTION Q-015**, **RISK R-006**.

### 4.6 Take cash payment and give change

1. Cashier tenders cash; the payment moves `pending -> tendered -> completed`.
2. **DECISION D-025** — Payment may begin at any of `submitted`/`accepted`/`preparing`/`ready`/`served`; it does **not** require the order to be ready or served first (quick-service **pay-first** is supported). Payment and fulfillment are independent: completing payment does **not** mark the food prepared/ready/served or the order completed.
3. Change is computed in integer minor units (no floating point — **DECISION D-007**); rounding rules are owned by [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md).
4. **DECISION D-023** — A `completed` payment is **terminal**: a void is allowed only **before** completion; `completed -> voided` is forbidden, and there is **no refund** in MVP (refunds are **DEFERRED**).
5. Fulfillment continues on its own track; the order reaches `completed` per its lifecycle in [STATE_MACHINES.md](STATE_MACHINES.md), and a receipt is printed (§4.5).
6. **DEFERRED** — Tips (**OPEN QUESTION Q-011**) and non-cash payment methods are out of MVP cash flow; see [MVP_SCOPE.md](MVP_SCOPE.md).

### 4.7 Void or discount with authorization

1. A void after submission requires authorization and a reason; the order/payment moves to a `voided` terminal state per [STATE_MACHINES.md](STATE_MACHINES.md).
2. **DECISION D-023/D-024** — A void is allowed **only before completion**. A `completed` payment is terminal (`completed -> voided` is forbidden), and a `completed` order is terminal; an order cancel/void is **rejected if a completed payment exists**. There is **no refund** in MVP (refunds are **DEFERRED**).
3. Void, cancellation, and refund are distinct concepts (refund is **DEFERRED**); the distinctions are owned by [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md).
4. **SECURITY REQUIREMENT** — A cashier cannot void an order without permission, and (per D-024) a void/cancel is rejected outright once a completed payment exists; every such action is captured as an append-only audit event with actor, device, scope, reason, and old/new values (**DECISION D-012/D-013**). This is part of the canonical isolation/permission test set.

### 4.8 Close shift and reconcile

1. The cash-drawer session moves to counting and is closed with a counted amount and computed variance (`active -> counting -> closed`).
2. The shift moves `open -> closing -> closed`, then both reach `reconciled` (terminal) after reconciliation.
3. Variance and reconciliation figures are computed in integer minor units per [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md).

### 4.9 Daily report

1. A manager/owner (or read-only accountant, **OPEN QUESTION Q-017**) opens the dashboard and views a daily report scoped to their membership.
2. The report summarizes orders, payments, voids/discounts, and cash reconciliation for the day; exact report contents are constrained by [MVP_SCOPE.md](MVP_SCOPE.md).

### 4.10 Cross-cutting offline behavior in journeys

Every mutating journey above produces operations that are queued locally and synchronized with idempotency keys (`device_id` + `local_operation_id`, **DECISION D-022**). A removed employee or revoked device must lose FUTURE access even across the offline window; the server rejects invalid operations on reconnect. The authoritative rules are owned by [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md) and [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md). **OPEN QUESTION Q-009**, **OPEN QUESTION Q-010**, **RISK R-002**, **RISK R-007**.

---

## 5. Multi-tenant SaaS framing & tenancy

RestoFlow is a single platform serving many independent restaurant customers, with strict isolation between them.

- **DECISION D-001** — `organization_id` is the primary tenant-isolation boundary; every tenant-scoped record carries it. Operational records additionally carry `restaurant_id`, `branch_id`, `device_id`, and `station_id` where relevant (naming per **DECISION D-017**, owned by [DOMAIN_MODEL.md](DOMAIN_MODEL.md)).
- **DECISION D-002** — Hierarchy: `Platform -> Organization -> Restaurant -> Branch -> Device/Station`. Both the independent-restaurant shape and the restaurant-group shape are first-class.
- **DECISION D-003** — The Organization is the tenant; the single-restaurant pilot is just an Organization with one Restaurant and one Branch.

Product implications:

- Customer onboarding creates an Organization (and its first Restaurant/Branch), never a globally-shared restaurant.
- All dashboards, reports, and POS/KDS views are scoped by membership within an organization.
- **SECURITY REQUIREMENT** — Org A can never read Org B's orders; a cashier in one restaurant cannot modify another; cross-tenant access and IDOR are prevented by the four-layer security model (**DECISION D-011/D-012**). The enforcement model and isolation tests are owned by [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md). **RISK R-003** (CRITICAL).
- **DEFERRED** — Self-serve tenant signup and billing are M4 (**OPEN QUESTION Q-016**); the pilot onboards a tenant operationally.

---

## 6. Localization

- **DECISION D-014** — RestoFlow supports **Arabic, Hebrew, and English**, with full **RTL** (ar, he) and **LTR** (en) layouts across every surface (POS, KDS, dashboard, platform admin).
- Localization applies to UI, receipts, and kitchen tickets; receipt/ticket localization and the Arabic/Hebrew printing encoding/raster fallback strategy are owned by [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md). **OPEN QUESTION Q-015**, **RISK R-006**.
- **ASSUMPTION** — English is the development/default fallback locale when a string is not yet translated; this does not weaken the requirement that all three languages ship.
- Currency and number formatting follow the per-organization currency (**DECISION D-007**), with the ISO 4217 code owned by [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md). **OPEN QUESTION Q-007**.

---

## 7. Non-goals for MVP

The authoritative in-scope / out-of-scope and DEFERRED list is owned by [MVP_SCOPE.md](MVP_SCOPE.md). This section only points to representative non-goals so product readers understand the boundaries; it does not define scope.

- **DEFERRED** — Non-cash/card payments and integrated payment processors.
- **DEFERRED** — Tips (**OPEN QUESTION Q-011**) and elaborate service-charge handling (**OPEN QUESTION Q-012**).
- **DEFERRED** — Refunds (the `refunded` payment state is deferred per the PROPOSED state enumerations (approved into the frozen M0A baseline (RF-004)) in [STATE_MACHINES.md](STATE_MACHINES.md)).
- **DEFERRED** — Self-serve signup, billing/subscriptions (**OPEN QUESTION Q-016**), and full platform-admin tooling (M4).
- **DEFERRED** — Reservations, delivery/marketplace integrations, loyalty, and advanced analytics.
- **OPEN QUESTION Q-017** — Whether the read-only `accountant` role ships in MVP or later.
- **RISK R-004** — Scope creep into deferred features is mitigated by the scope frozen as the M0A baseline at RF-004 plus a human approval gate (**DECISION D-016**).

For milestone sequencing (M0A through M4) and timeline, see [PROJECT_PLAN.md](PROJECT_PLAN.md) (**DECISION D-019**).

---

## 8. Cross-references (document map)

- [DECISIONS.md](DECISIONS.md) — decision log (D-xxx), authoritative.
- [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) — open-questions register (Q-xxx), authoritative.
- [MVP_SCOPE.md](MVP_SCOPE.md) — in/out scope and DEFERRED list.
- [DOMAIN_MODEL.md](DOMAIN_MODEL.md) — entities, fields, relationships, naming.
- [STATE_MACHINES.md](STATE_MACHINES.md) — PROPOSED state enumerations and transitions (approved into the frozen M0A baseline (RF-004)).
- [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md) — money, tax, receipts, discounts.
- [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) — identity, roles, RLS, threats, isolation tests.
- [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md) — offline-first, outbox/inbox, idempotency, reconciliation.
- [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md) — printing/hardware, localization of print.
- [API_CONTRACT.md](API_CONTRACT.md) — RPC/endpoint contracts.
- [ARCHITECTURE.md](ARCHITECTURE.md) — system structure.
- [PROJECT_PLAN.md](PROJECT_PLAN.md) — milestones, timeline, ownership.
