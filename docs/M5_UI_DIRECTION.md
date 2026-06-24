# M5 UI Direction — RestoFlow Demo UI Track

> **STATUS — ADVISORY / SUBORDINATE.** This is a **working reference** for the
> **M5 "Usable Demo UI" track**, a UI-first phase started **after** the original
> frozen **M0A–M4** plan. It is **not** a frozen or governance document. If
> anything here conflicts with the frozen canon — [../CLAUDE.md](../CLAUDE.md),
> [DECISIONS.md](DECISIONS.md), [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md),
> [PROJECT_SPEC / PRODUCT_SPEC.md](PRODUCT_SPEC.md), or any owning spec — **the
> frozen canon wins**. This doc never restates rules owned elsewhere; it
> **links** to them.
>
> **M5 is not a formal milestone.** The frozen milestone ladder is **M0A–M4**
> (DECISION **D-019**, owned by [PROJECT_PLAN.md](PROJECT_PLAN.md)). "M5" and the
> **RF-100+** ticket range are a **working UI demo track created after** that
> plan; they are **not** part of D-019 and have **no** backlog rows yet. If Saleh
> later wants M5 to become a formal milestone (or RF-100+ to enter the backlog),
> that is a **separate architecture / change-control decision** (new ticket +
> independent review + human approval per [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md)
> §9) — it must **not** be assumed from this file.

---

## 1. Purpose

Give future UI tickets a small, consistent reference so demo-UI work stays true
to the product, honours the binding invariants, and looks/behaves coherently
across surfaces. Pair this with [M5_UI_WORKFLOW.md](M5_UI_WORKFLOW.md) (how to
run the work) — this file is **what to build and the rules it must respect**.

## 2. What RestoFlow is

RestoFlow is a **multi-tenant Restaurant Operating System (Restaurant OS)
delivered as SaaS — not just a POS.** It is the system of record for orders,
payments, shifts, and operational state for **many independent restaurant
customers on one platform**, with strict tenant isolation, offline-first
operation, printing, cash payments, shifts, and reporting. Full product framing
lives in [PRODUCT_SPEC.md](PRODUCT_SPEC.md); structure in
[ARCHITECTURE.md](ARCHITECTURE.md).

- **Tenant = Organization** (DECISION **D-003**). Hierarchy
  `Platform → Organization → Restaurant → Branch → Device/Station` (**D-002**);
  `organization_id` is the isolation boundary (**D-001**; cross-tenant leakage is
  **RISK R-003**, CRITICAL).
- **Roles are membership-scoped**, never a global role (**D-004/D-005**):
  `org_owner, restaurant_owner, manager, cashier, kitchen_staff, accountant`
  (accountant read-only). `platform_admin` is **not** a membership role
  (**D-026**).

> A demo UI may use fake tenants/data, but it must **never bake in a
> single-org/single-restaurant/single-branch assumption** (D-001/D-002/D-003).

## 3. Who uses each surface

| Surface | App | Primary users | What it is for |
|---|---|---|---|
| **POS** | `apps/pos` | cashier (PIN on a paired device) | Build dine-in/takeaway orders, discounts, submit to kitchen, take **cash** payment + change, print, work offline with **visible sync status**. |
| **KDS** | `apps/kds` | kitchen staff (branch + station) | Show kitchen tickets / station items; acknowledge → in-preparation → ready → bump + audited recall. **Never shows money or financial data.** |
| **Dashboard** | `apps/dashboard` | owner / restaurant owner / manager / accountant (read-only) | Membership-scoped shift status, cash reconciliation, daily reports, staff/device governance entry points. |
| **Platform Admin** | `apps/admin` | platform operator (separate, audited path) | Cross-org onboarding / suspension / support. **Isolated from tenant flows**; not reachable via tenant navigation (**D-026**, audited per **D-013**). |

Surface detail is owned by [PRODUCT_SPEC.md](PRODUCT_SPEC.md) §3.

## 4. Current UI inventory (as of this M5 track)

| App | State | Notes |
|---|---|---|
| `apps/pos` | **Real / polished** | Menu grid + cart, Riverpod, themed via `packages/design_system`, l10n, integer-minor money, demo Send Order. The current visual reference. |
| `apps/kds` | **Usable, needs polish** | Real screen (tickets by station, bump/recall via the kitchen state machine), Riverpod + l10n — but does **not** apply the shared theme/tokens; renders raw `status.canonicalName`; loading/reauth/error are icon-only. |
| `apps/dashboard` | **Shell** | ~38-line localized welcome screen; no Riverpod, no theme, no screens. Needs real UI. |
| `apps/admin` | **Shell** | Same as dashboard. Needs real UI. |

## 5. UI design principles (the demo bar)

1. **Visible demo progress first.** Prefer a real, runnable screen over backend
   wiring. Every UI ticket should end with something you can **see in Chrome**.
2. **Match the POS reference.** New surfaces should feel like the POS screen:
   themed, spaced, real controls — not a debug dump.
3. **State-correct, not state-inventive.** Render entity status **only** from the
   PROPOSED enumerations in [STATE_MACHINES.md](STATE_MACHINES.md) (DECISION
   **D-018**). Do **not** add, rename, or repurpose states. Treat **payment and
   fulfillment as independent tracks** (**D-025**); completed order/payment are
   terminal with **no in-app refund** (**D-023/D-024**).
4. **Role- and tenant-correct.** Gate by membership scope; **KDS shows no money**;
   keep platform admin isolated. Never render cross-tenant data.
5. **Standard empty / loading / error / status patterns.** Give every async
   surface a real empty state and a localized loading/error message (close the
   KDS icon-only gap), and present status as a styled, localized label.
6. **Accessible & responsive.** Looks right in desktop Chrome and degrades
   sanely at narrower widths.

## 6. Design-system direction

- Build UI through **`packages/design_system`**: apply **`restoflowBaseTheme()`**
  (seeded Material 3, light + optional dark) on every `MaterialApp`, and use the
  **`RestoflowSpacing` / `RestoflowRadii`** tokens (+ `kRestoflowSeedColor`)
  instead of hardcoded `EdgeInsets`/radii.
- **Standardize adoption:** dashboard, admin, and kds should all depend on and
  apply the shared theme (today only POS does).
- **State management = Riverpod** (DECISION **D-009**): `ProviderScope` at the
  app root, `ConsumerWidget` + `AsyncValue.when` for data-driven screens (the KDS
  pattern). **Routing = GoRouter** (D-009) once a surface needs more than one
  screen. Keep screens/widgets under `lib/src/{state,widgets,screens}`.
- design_system is a **shared package**: substantive changes to it are their own
  ticket and follow [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9 (small, additive,
  tested). Architectural intent: [ARCHITECTURE.md](ARCHITECTURE.md) §3.

## 7. Localization & RTL/LTR direction

- **All three languages ship: Arabic, Hebrew, English**, with **full RTL (ar,
  he) and LTR (en)** on every surface (DECISION **D-014**). English is the dev
  fallback.
- **All UI chrome goes through l10n** (`AppLocalizations` from
  `packages/l10n`); no hardcoded user-facing strings (the
  `check_no_hardcoded_strings` guard enforces this for app shells). **Data**
  (menu/item/category names, ids) is rendered via variables and may be demo data,
  not l10n keys.
- **Direction is data-driven** via the shared localization delegates
  (`restoflowLocalizationsDelegates`, `kSupportedLocales`,
  `restoflowResolveLocale`) — **never** wrap UI in a manual `Directionality`; use
  `EdgeInsetsDirectional` / directional alignment for layout.
- Adding strings: edit `app_en.arb` + `app_ar.arb` + `app_he.arb` (keys must
  stay in parity — the ARB completeness test enforces it), then regenerate the
  committed `AppLocalizations`.

## 8. Money display rules

- **Money is integer minor units everywhere — no floating-point currency math**
  (DECISION **D-007**). Use the **`packages/money`** `Money` type and a shared
  formatter; never type a money value as `double`/`num` (the `check_no_float_money`
  guard enforces this). Full rules: [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md).
- **Show order-time snapshots, not live menu prices** (**D-008**): editing the
  menu must never retroactively change amounts on an existing/open order.
- A single currency per order (Q-007 open); render the currency symbol/decimals
  in the display layer, keep the stored/computed value in minor units.

## 9. Fake/demo data rules

- **Use fake/in-memory demo data first** where a real data source isn't the point
  of the ticket. Keep demo data isolated in a single data file/section so it can
  be swapped for a real source later.
- Demo data must still respect the invariants: integer-minor prices, valid status
  values, tenant-shaped ids, localizable names.
- Placeholders for not-yet-built capability are fine (e.g. a disabled button or a
  "coming later" notice), **but no UI dedicated to a deferred feature** (scope
  guardrail **RISK R-004**; deferred list in [MVP_SCOPE.md](MVP_SCOPE.md) §3).

## 10. Out of scope (for M5 UI tickets and for this doc)

- **No backend expansion in a UI ticket unless that ticket explicitly approves
  it.** No `supabase/**`, migrations, RLS, RPCs, DB schema, CI, production config,
  remote Supabase, or secrets. No real `submit_order`, payments, auth/PIN, or
  persistence in demo UI unless explicitly ticketed.
- **No deferred-feature UI** (card/online payments, delivery, loyalty, refunds,
  tips, advanced reservations, advanced cross-branch console, billing/signup) —
  see [MVP_SCOPE.md](MVP_SCOPE.md) §3.
- **This doc does not** define a milestone, renumber tickets, amend D-019, or
  restate rules owned by [STATE_MACHINES.md](STATE_MACHINES.md),
  [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md),
  [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md),
  [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md),
  [DOMAIN_MODEL.md](DOMAIN_MODEL.md), or
  [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md).

---

### Owning-doc map (where the real rules live)

| Topic | Owner |
|---|---|
| Product vision / surfaces / personas | [PRODUCT_SPEC.md](PRODUCT_SPEC.md) |
| System structure / stack | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Entities / fields | [DOMAIN_MODEL.md](DOMAIN_MODEL.md) |
| Status enumerations / transitions | [STATE_MACHINES.md](STATE_MACHINES.md) |
| Money / tax / receipts | [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md) |
| Security / RLS / isolation | [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) |
| Offline / sync | [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md) |
| Decisions (D-xxx) / open questions (Q-xxx) | [DECISIONS.md](DECISIONS.md) / [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) |
| In/out of MVP scope | [MVP_SCOPE.md](MVP_SCOPE.md) |
| Workflow / DoR / DoD | [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) |
| **How to run M5 UI work** | [M5_UI_WORKFLOW.md](M5_UI_WORKFLOW.md) |
