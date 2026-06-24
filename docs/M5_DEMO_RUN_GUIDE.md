# M5 Demo Run Guide — RestoFlow POS / KDS / Dashboard

> **STATUS — ADVISORY / DEMO.** This guide explains how to run and read the
> **M5 "Usable Demo UI"** apps. Everything here is **in-memory, local, demo
> data** — nothing connects to a backend. This is a working guide, **not** a
> frozen/governance document; if it ever conflicts with the frozen canon
> ([../CLAUDE.md](../CLAUDE.md), [DECISIONS.md](DECISIONS.md)) or the owning
> specs, the frozen canon wins. Companion docs:
> [M5_UI_DIRECTION.md](M5_UI_DIRECTION.md) (what to build + invariants) and
> [M5_UI_WORKFLOW.md](M5_UI_WORKFLOW.md) (how the work is run).

The three M5 demo apps run independently in Chrome. They are **not live-wired to
each other** — there is no real data flowing POS → KDS → Dashboard. Instead they
share a single **fictional restaurant story** so the demo reads as one coherent
business.

## The shared demo story

- **One fictional organization**, single currency **ILS (₪)**.
- **Branches:** Downtown, Seaside, Airport (shown on the Dashboard).
- **Shared dish vocabulary** — the POS menu
  ([apps/pos/lib/src/data/demo_menu.dart](../apps/pos/lib/src/data/demo_menu.dart)):
  Classic Burger, Grilled Chicken, Margherita Pizza, Falafel Plate, French
  Fries, Onion Rings, Cola, Fresh Lemonade, Espresso, … The KDS tickets and the
  Dashboard "top items" reuse these same names.
- **Narrative:** a cashier builds an order on **POS**; the kitchen works its
  tickets on **KDS**; an owner/manager reviews the day on the **Dashboard**.
  The link between surfaces is this shared story (names/currency/branches), **not**
  live data.

## Run each demo in Chrome

From the repo root, run one app at a time (each is a separate Flutter app):

```bash
# POS — cashier menu + cart + local submit-order confirmation
cd apps/pos && flutter pub get && flutter run -d chrome

# KDS — kitchen board with lifecycle actions
cd apps/kds && flutter pub get && flutter run -d chrome

# Dashboard — owner/manager demo report cards
cd apps/dashboard && flutter pub get && flutter run -d chrome
```

To build (without launching) instead of `run`, use `flutter build web` in the
same directory. Try a right-to-left locale (Arabic/Hebrew) via your browser/OS
language to see RTL — direction is data-driven by the shared l10n delegates.

## What each app shows

| App | What you see |
|---|---|
| **POS** (`apps/pos`) | A category-filtered menu grid and a live cart panel (add / quantity / remove / clear, running subtotal in ₪). Tapping **Send Order** shows an in-place local confirmation with a provisional demo order number (`DEMO-0001`). |
| **KDS** (`apps/kds`) | A themed kitchen board grouping tickets by station (grill / fryer), with color-coded status chips and one lifecycle action per ticket: **Acknowledge → Start → Mark ready → Bump**, plus **Recall**. Tickets load across multiple statuses. **No money is shown** (kitchen redaction). |
| **Dashboard** (`apps/dashboard`) | An owner/manager day-summary: KPI cards (today's sales, orders, average order value, completed/open orders), a daily summary (net sales, discounts, voids, cash collected, cash variance, shift status), a sales-by-branch list, and a top-items list — all in ₪. |

## Real domain logic vs fake/local data

The demos render **fake/in-memory data**, but POS and KDS exercise **real
domain logic** from the shared packages:

- **POS** uses the **real** in-memory `Cart` and `LocalOrder.submitFromCart`
  (`packages/domain`) and the **real** integer minor-unit money type
  (`packages/money`). The menu items and order number are demo data.
- **KDS** uses the **real** `KitchenTicketStateMachine` (`packages/domain`) for
  every Acknowledge/Start/Mark-ready/Bump/Recall transition. The tickets are
  demo data.
- **Dashboard** renders a **fake** in-memory report (no domain/state-machine);
  its field shapes mirror the real report views for forward-compatibility, but
  nothing is computed from real orders. Money is integer minor units; the
  average order value uses **integer division** (no floating-point money).

## What is intentionally NOT wired yet

- **No real `submit_order`** — POS "Send Order" is a local confirmation only.
- **No backend / Supabase / RPC / report-view** live flow — every surface is
  in-memory; nothing is fetched or persisted.
- **No live POS → KDS → Dashboard data flow** — the apps are independent; the
  shared story is documentation, not runtime data.
- **No auth / session / role-scoped real data** — no login, PIN, or membership
  scoping; the Dashboard shows a single demo report, not a real role-scoped view.
- **No printing / payment / offline-sync** live flow.

## Quick validation

```bash
dart format --output=none --set-exit-if-changed .
dart analyze .
flutter test apps/pos
flutter test apps/kds
flutter test apps/dashboard
flutter test packages/l10n
bash tools/check_no_hardcoded_strings.sh
bash tools/check_no_float_money.sh
dart run tools/check_l10n.dart
cd apps/pos && flutter build web          # repeat for apps/kds, apps/dashboard
```

## Where the demo data lives (isolated & swappable)

Each app keeps its demo data in one isolated file (no fake data scattered in
reusable widgets), so it can later be swapped for a real source:

- POS menu: [apps/pos/lib/src/data/demo_menu.dart](../apps/pos/lib/src/data/demo_menu.dart)
- KDS tickets: [apps/kds/lib/src/data/demo_tickets.dart](../apps/kds/lib/src/data/demo_tickets.dart)
- Dashboard report: [apps/dashboard/lib/src/data/demo_report.dart](../apps/dashboard/lib/src/data/demo_report.dart)
