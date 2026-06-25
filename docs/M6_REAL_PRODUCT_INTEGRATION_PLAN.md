# M6 — Real Product Integration / Sellable Restaurant Demo (Direction Plan)

> **STATUS — ADVISORY / SUBORDINATE.** This is the **working direction** for the
> **M6 "Real Product Integration"** track. M6 is a **post-plan track** that comes
> after the frozen **M0A–M4** ladder (DECISION **D-019**) and the **M5 UI demo**
> phase — it is **not** itself a frozen milestone. If anything here conflicts
> with the frozen canon ([../CLAUDE.md](../CLAUDE.md), [DECISIONS.md](DECISIONS.md),
> [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md), or any owning spec), **the frozen canon
> wins**. Companions: [M6_JIRA_BACKLOG.md](M6_JIRA_BACKLOG.md) (ticket detail) and
> [M6_JIRA_IMPORT.csv](M6_JIRA_IMPORT.csv) (Jira import). Sits alongside the M5
> docs: [M5_UI_DIRECTION.md](M5_UI_DIRECTION.md), [M5_UI_WORKFLOW.md](M5_UI_WORKFLOW.md),
> [M5_DEMO_RUN_GUIDE.md](M5_DEMO_RUN_GUIDE.md).

## 1. M6 framing

**Goal of M6:** turn RestoFlow from a UI demo into a **connected restaurant
operations product demo that feels close to real use** — a *sellable restaurant
demo*. An owner manages a real restaurant (settings, users/roles, menu, tables);
a cashier takes real orders and cash payments on the POS; kitchen staff work
real tickets on the KDS; the owner sees real numbers on the dashboard; receipts
and kitchen tickets render as a clear browser print preview.

## 2. Current state after M5

- **M5 complete (RF-100→RF-106):** POS, KDS, Dashboard are real, themed, l10n,
  RTL/LTR, integer-minor **demo** surfaces with Chrome `web/` targets; Admin is a
  localized shell. M5 advisory docs exist.
- **Demo-only today:** POS (in-memory `demo_menu.dart` + local `Cart` /
  `LocalOrder.submitFromCart`, no auth), Dashboard (in-memory `demo_report.dart`),
  Admin (shell). **KDS already has the real backend path built but unactivated** —
  the synced path runs only if a `KdsSyncSource` is injected; the demo injects
  none, so it shows a fixture.
- **Backend foundation already exists and is production-grade (RF-014→RF-094):**
  multi-tenant schema; Supabase Auth + MFA binding; PIN sessions; orders /
  discount / void / payment / shift RPCs (server **recomputes & validates**
  totals, per-branch receipt numbering); `sync_push` / `sync_pull`; full RLS with
  kitchen money redaction; reporting views (RF-075/092); billing (RF-093);
  platform admin (RF-091); 122 pgTAP tests.
- **Client packages already real:** `core`, `data_local` (Drift + outbox/inbox +
  `MenuRepository` + durable print spool), `data_remote` (Supabase transport +
  `SyncPullApi`; the only file importing the Supabase SDK — D-011-safe), `sync`
  (`KdsSyncCoordinator`), `feature_kitchen`, `printing` (full ESC/POS + spool +
  receipt/kitchen builders + Arabic/Hebrew rasterizer + drawer kick).
- **Empty stubs:** `auth_identity`, `feature_orders`, `feature_menu`,
  `feature_payments`, `feature_shifts`, `feature_reporting`.

## 3. "Connect, don't rebuild"

The backend and most client plumbing **already exist**. M6 is overwhelmingly
**client wiring of existing backend** — implement the stub feature packages,
wire a real Supabase session, and activate the already-built data paths.

A **small amount of genuinely new backend** is required and is fenced off into
isolated, change-controlled tickets: **menu schema/RLS/RPC + sync**, **image
storage bucket/policies**, **settings/users/devices provisioning RPCs**, a small
**tables** entity, and a small **kitchen status-action RPC**. These amend the
frozen baseline and must follow the architecture-change procedure
([AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9; see §10 guardrails and candidate
D-030 in §11).

## 4. M6 "done" statement

**A reviewer can log into one demo restaurant and, end to end:** an owner manages
real menu/settings/users; a cashier takes a real order (real menu → cart with
options/notes/table/order-type → server `submit_order` → cash payment → receipt)
that **survives a page refresh and reconciles offline**; that order appears
**live on KDS**, where kitchen staff advance its status against the backend; the
owner sees the day's **real numbers** on the dashboard; and receipts / kitchen
tickets render as a **clear browser print preview** — all on real Supabase data
with tenant isolation, integer-minor money, ar/he/en RTL, and **no hardware
assumed**.

## 5. Fake/demo vs real — per surface

| Surface | Becomes REAL in M6 | Stays simulated / deferred |
|---|---|---|
| Auth / session | login, device pairing, PIN, role/scope resolution | full MFA UX polish (Q-008), self-serve signup |
| Menu | server menu + sync + owner CRUD + images | inventory/stock, scheduling |
| POS order | `submit_order` via outbox, options/notes/table/type, sync status | discount/void UI may lag a ticket |
| Payment | cash payment + receipt number + shift | **card/online, refunds, tips, service charge** |
| KDS | live orders + backend status actions | advanced routing-rule polish |
| Printing | receipt/ticket **content** + **browser preview** | **hardware printing + drawer kick** (no hardware) |
| Dashboard | real RF-075/092 reports | analytics / trends / charts |
| Admin | platform overview (RF-091) | impersonation, grant/revoke admin |
| Tables | branch table **list** + assignment + order type | **visual floor map**, reservations |
| Realtime | optional enhancement (polling is the real path) | realtime as source of truth (never) |

**Rule:** any surface that stays simulated keeps its fake data **isolated and
swappable** in an app-level `src/data/` file (never scattered in widgets), behind
a provider/repository so it can be swapped for the real source later.

## 6. Menu / images plan

- **Menu backend (new, change-controlled — RF-109 / DECISION D-031):** `menu_categories`,
  `menu_items`, `item_sizes`, `item_variants`, `modifiers`, `modifier_options`
  with **integer `_minor` prices** (`base_price_minor` / signed `price_delta_minor`),
  `currency_code`, availability/`is_active`, tenant columns (org + restaurant +
  nullable `branch_id`), **RLS** (owner/manager write; **price-capable roles
  read** — `kitchen_staff` excluded), **audited management RPCs**, and **added to
  `sync_pull`** so **price-capable POS roles** get the menu offline. **`kitchen_staff`/KDS
  do NOT pull the live menu** (it carries price/money); KDS shows item names from
  **order snapshots** (**D-008**), not the live menu. The client Drift mirror
  (`MenuRepository` in `data_local`) already exists.
- **Order snapshots stay authoritative (D-008):** editing the menu never rewrites
  prices/names on existing or historical orders.
- **Categories / prices / availability / modifiers-options:** all first-class;
  prices integer minor units only.
- **Images (new, change-controlled — RF-110):** a Supabase **Storage bucket** with
  **org-path-scoped RLS** and signed-URL/upload; uploaded from the owner menu UI;
  no public PII; size/MIME limits.

## 7. Tables / order-type plan

- **In scope (RF-114):** a per-branch **table list** (number/label/seats/area,
  `is_active`), a POS **dine-in / takeaway** order-type selector, and **table
  assignment** to a dine-in order (`orders.table_id` already exists). Reuse the
  domain `TableAssignmentService` rule (one open dine-in order per table).
- **Out of scope:** a **visual floor map / drag-drop**, reservations, table
  merge/split (deferred).

## 8. Printing plan

- **Kitchen ticket / customer receipt content:** reuse the existing
  `printing` builders — `KitchenTicketPrintBuilder` (money-free, station-routed),
  `CustomerReceiptPrintBuilder` + `ReceiptMoneyFormat` (integer-only), and the
  Flutter Arabic/Hebrew rasterizer. Receipt numbers come from `record_payment`
  (D-021).
- **Browser/web demo (RF-118):** ESC/POS **bytes cannot print from a browser**,
  so the demo renders a **clean HTML/PDF preview** (`window.print()`) from the
  same document model, clearly labeled "demo print".
- **Future hardware:** keep the ESC/POS adapter + transport port + durable spool
  intact; real printing/drawer-kick needs a **future native local print bridge**
  (USB/network/Bluetooth), gated by Q-006/Q-015. **No hardware is assumed.**

## 9. Permissions plan (who can do what)

- **platform_admin** — separate, not a membership role (DECISION **D-026**),
  MFA-gated, explicitly audited; cross-org overview, onboarding/suspension, plans
  (RF-091/093) → `apps/admin`.
- **org_owner / restaurant_owner** — settings, menu, users/roles, device pairing,
  branch reports, void/discount authority → owner UI (dashboard/admin).
- **manager** — branch ops, shift open/close, authorize voids/discounts,
  reconcile, branch reports.
- **cashier** — order build, cash payment, receipts; **cannot void/discount
  beyond limit without manager authorization; cannot void a paid order** (D-024).
- **kitchen_staff** — KDS tickets/status only; **never sees money** (RLS
  redaction; canonical isolation test).
- **accountant** — read-only reports; no state-changing RPC (denied close /
  reconcile, D-028); **may not ship in MVP** (Q-017).

## 10. Dangerous areas & guardrails

**Dangerous areas:** auth/security/RLS and tenant isolation (**RISK R-003**,
CRITICAL — every new table/RPC/storage policy is a fresh RLS surface);
money/payment accuracy (D-007); printing/hardware assumptions; image/storage
permissions; offline sync conflicts; role permissions.

**Guardrails (binding for every M6 ticket):**

- **No huge PR.** **One branch/PR per meaningful chunk** (keep the M5 cadence:
  local checkpoints → Codex review → human merge).
- **Backend / RLS / storage changes are isolated, Codex-reviewed tickets** (their
  own branch/PR) and follow the architecture-change procedure
  ([AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) §9): a DECISIONS entry + independent
  review + human approval, with the **RF-060 isolation suite green** before merge.
  They are never folded into a UI ticket.
- **No weakening RLS.**
- **No service-role key in clients** (DECISION **D-011**); sensitive mutations go
  through SECURITY DEFINER RPCs.
- **No float money;** **server recomputes and validates order totals** and rejects
  mismatches (DECISION **D-007**); integer minor units everywhere.
- **Kitchen remains money-free** (RLS redaction preserved).
- **Platform admin stays separate from tenant roles** (DECISION **D-026**).
- **Printing hardware is not assumed** — browser preview only; real printing is a
  future native local bridge.
- **Image storage must be tenant-scoped** (org-path RLS; no cross-tenant; no
  public PII).
- **Fake data stays isolated and swappable** (app-level `src/data/` files behind a
  provider/repository; never scattered in reusable widgets).

## 11. Candidate DECISION D-030 (CANDIDATE ONLY — not ratified)

> **CANDIDATE — pending owner (Saleh) approval. NOT yet ratified into
> [DECISIONS.md](DECISIONS.md).** Recorded here under RF-107 so M6 has a written
> governance basis; it becomes binding only when the human owner approves it via
> the architecture-change procedure and it is added to DECISIONS.md.

**D-030 (candidate) — M6 is a post-plan integration track.**

1. **M6 ("Real Product Integration / Sellable Restaurant Demo") is a post-plan
   track**, sequenced after the frozen M0A–M4 ladder (D-019) and the M5 UI demo
   phase. It is **not** a new frozen milestone and does **not** amend D-019 unless
   a separate decision explicitly does so. Most M6 work is the **client half of
   M2** (auth/session, outbox push, order/payment/shift/reporting clients) wired
   to the already-built backend.
2. **Any new backend surface introduced by M6** — menu schema/RLS/RPC and its
   `sync_pull` exposure (RF-109), image storage bucket/policies (RF-110),
   settings/users/devices provisioning RPCs (RF-112), the tables entity (RF-114),
   and the kitchen status-action RPC (RF-117) — **amends the frozen baseline and
   must follow the architecture-change procedure**: its own ticket, a DECISIONS
   entry, independent (Codex) review, human approval, and the RF-060 tenant
   isolation suite green before merge. No new schema/RLS/RPC/storage is folded
   into a UI ticket.
3. **The frozen invariants remain binding** in M6: integer-minor money with
   server-side recompute (D-007/D-008), offline-first idempotency (D-010/D-022),
   no service-role key in clients (D-011), fixed state enumerations (D-018),
   per-branch receipt numbering (D-021), terminal completed/no-refund (D-023/
   D-024), platform-admin separation (D-026), and tenant isolation (D-001,
   RISK R-003).
4. **D-030 is a candidate only.** Until approved, M6 implementation tickets that
   touch frozen backend/schema/contracts must not begin; pure client-wiring/UI
   tickets proceed under the advisory M5/M6 demo track.

---

### Owning-doc map (where the real rules live)

| Topic | Owner |
|---|---|
| Decisions (D-xxx) / open questions | [DECISIONS.md](DECISIONS.md) / [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md) |
| Product surfaces / personas | [PRODUCT_SPEC.md](PRODUCT_SPEC.md) |
| In/out of MVP scope | [MVP_SCOPE.md](MVP_SCOPE.md) |
| Entities / fields | [DOMAIN_MODEL.md](DOMAIN_MODEL.md) |
| Status enumerations / transitions | [STATE_MACHINES.md](STATE_MACHINES.md) |
| Money / tax / receipts | [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md) |
| Security / RLS / isolation | [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) |
| Offline / sync | [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md) |
| Printing / hardware | [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md) |
| Workflow / DoR / DoD / change-control | [AGENT_WORKFLOW.md](AGENT_WORKFLOW.md) |
| **M6 ticket detail** | [M6_JIRA_BACKLOG.md](M6_JIRA_BACKLOG.md) |
| **M6 Jira import** | [M6_JIRA_IMPORT.csv](M6_JIRA_IMPORT.csv) |
