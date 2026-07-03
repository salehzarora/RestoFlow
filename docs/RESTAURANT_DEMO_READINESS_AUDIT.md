# RestoFlow — Restaurant Demo Readiness Audit

> Status of the visible product as of the demo-readiness sprint (2026-07-03,
> branch `feature/product-rescue-visible-mvp`). This is the honest checklist
> for showing RestoFlow to a restaurant owner on a local machine. Companion
> how-to: [LOCAL_RUNBOOK.md](LOCAL_RUNBOOK.md).

---

## 1. READY — works end to end, for real, locally

| Area | State |
|---|---|
| **Launch** | Stable-port scripts (`_run_dashboard_real.bat` 57026, `_run_pos_real.bat` 52096, `_run_kds_real.bat` 49622) keep browser-origin storage stable, so sign-in and device pairing survive restarts. |
| **Language** | First launch is **Arabic, RTL**. A visible switcher (AR/HE/EN) on every surface — dashboard header + sign-in, POS/KDS pairing, PIN, and main screens, admin overview. The choice persists per device/browser. |
| **Currency** | **ILS only**: new orgs onboard with ILS; menus, POS, receipts, and reports render ₪; demo data mirrors it. Money is integer minor units everywhere. |
| **Owner onboarding** | Sign-up → restaurant name → org/restaurant/branch/station created; Real pill; guided Setup checklist on Overview (menu → devices → pairing → printer → staff PIN) with a fixing button per step. |
| **Menu** | Real CRUD from the dashboard: categories, items (₪, minor units), sizes/variants/**modifier groups + options** (free and paid, required/min/max), enable/disable, soft delete. The paired POS sells exactly this menu. |
| **Tables** | Real management (Tables tab): create/edit (name, seats, area), 4 statuses (available/occupied/reserved/out of service), activate/deactivate, delete. The POS picker loads the branch's real tables (statuses gate assignability); the KDS shows the table label on the ticket. |
| **Devices** | Create POS/KDS devices, one-time pairing codes (hash-stored, ~15 min), revoke. Devices pair themselves via anonymous sign-in; sessions are type-checked per surface and restored across restarts. |
| **Staff/PINs** | Real staff + bcrypt PINs from the dashboard; the paired device lists branch staff; wrong PIN denied/rate-limited; correct PIN opens a session (POS auto-opens the required server shift). |
| **POS order flow** | Real mode is fully real: no demo labels, no manual sync. Items with modifier groups open the option picker (required groups enforced, live ₪ deltas). Submit **sends automatically** to the backend; failures show an honest error + Retry (never a pretended send). Cash payment returns the **server receipt number**. |
| **POS ↔ KDS numbering** | Both show the SAME human order code (`#XXXXXX`, derived identically from the order id). The receipt number is the fiscal number once paid. |
| **KDS** | Live board in workflow columns **New → Preparing → Ready → Cleared**; tickets move on Acknowledge/Start/Ready/Bump; cards show order code, dine-in/takeaway, table, station, quantities, structured `+ modifier` lines, and notes. Zero money on kitchen surfaces (server-side redaction + client allowlist). Updates arrive via 5s polling plus an immediate refresh after each action. |
| **Reports** | Overview reads the real `sales_summary` (orders today, payments, gross ₪, 7-day series) with manual refresh. |
| **Backend integrity** | 168 pgTAP files / 2,641 assertions green: tenant isolation, role gates, idempotency, money validation, kitchen redaction. |

## 2. PARTIALLY READY — visible and honest, but limited

- **Printers** — the guided 3-step wizard saves real, validated configuration
  (network host + advanced port; Bluetooth/USB honestly marked as needing the
  print bridge) and routes to stations. **Nothing prints**: no transport is
  installed; the Test print button exists but is disabled with an explanation.
- **Order flow edge cases** — status pushes are fire-and-forget (the poll
  corrects); POS has no in-place dead-session recovery (KDS offers "Sign in
  again"); modifiers on the KDS come from the POS flow, while sizes/variants
  are managed in the dashboard but not yet sellable on the POS.
- **Tables ↔ orders lifecycle** — the order carries the table and the KDS
  shows it, but tables are **not auto-marked occupied** when an order is sent;
  a manager sets statuses manually in Dashboard → Tables (a device-originated
  `table.status` sync op is the follow-up).
- **Shifts** — a real shift auto-opens at PIN sign-in (payments require it),
  but there is no close/reconcile UI and no real opening float.
- **Realtime** — the backend emits KDS invalidation hints, but the client is
  polling-first (5s + immediate refresh after actions); good enough to look
  instant in a demo.

## 3. NOT READY — do not show as working

- **Users tab** — honest "not connected yet" (no member read API).
- **Settings tab** — read-only real values; no editing round-trip.
- **Physical printing** — no receipt/ticket ever reaches hardware.
- **Discounts, voids UI, taxes, non-cash tenders** — payment is CASH only,
  no discount/tax engine on the POS.
- **Offline-first on device** — the outbox is in-memory per session; a closed
  browser tab loses an UNSENT (failed-push) order. Real Drift/SQLite
  persistence is the M2 offline milestone.
- **Platform admin app** — read-only limited overview; no MFA/grant management.

## 4. Exact manual demo script (fresh machine, ~20 minutes)

1. `supabase stop` → `supabase start` → `supabase db reset`.
2. Double-click `_run_dashboard_real.bat`. **Expect Arabic RTL**; switch
   language from the header if desired (persists).
3. Sign up (email + password) → restaurant name → you land on the shell:
   Real pill, Setup checklist.
4. **Menu**: add category "مشروبات/Drinks", items with prices (₪); for a
   burger add modifier groups (Toppings; required single-select Doneness;
   paid Extras).
5. **Tables**: add T1–T4 (seats/areas).
6. **Devices**: create one POS + one KDS; Issue code for each.
7. `_run_pos_real.bat` + `_run_kds_real.bat` → each shows its pairing screen
   → enter the matching codes.
8. **Staff**: add a cashier + kitchen staff, set PINs. On POS/KDS tap **Try
   again** → names appear → sign in with PINs (POS = cashier, KDS = kitchen).
9. POS: choose dine-in → pick T2 → add the burger (option picker appears —
   choose doneness/toppings; watch the ₪ total) → Send. The confirmation
   shows `#XXXXXX`, "Sent — the kitchen display receives it automatically".
10. KDS: the ticket appears in **New** with the SAME `#XXXXXX`, table T2, and
    the `+ modifier` lines → Acknowledge → Start → Ready → Bump; it moves
    columns each tap.
11. POS: Pay Cash → the server receipt number appears on the receipt preview.
12. Dashboard Overview → Refresh → today's order + gross ₪ update.
13. Printers: walk the wizard, save a network printer, show the honest
    "Configured only / Test print unavailable" state.

## 5. Known limitations to say out loud in a demo

- Printing is configuration-only (hardware arrives with the print bridge).
- One payment method (cash); no discounts/taxes yet.
- If the browser tab closes before a failed send is retried, that order is
  lost (offline persistence is a later milestone).
- Users/Settings management pages are placeholders.
- Table statuses are manager-maintained (no auto-occupy yet).

## 6. Requires hardware / a native app

- ESC/POS printing (network/Bluetooth/USB) — the engine exists
  (`packages/printing`), transports are human-gated (Q-006/Q-015); Bluetooth
  and USB additionally need the desktop/native print bridge (web cannot scan).
- OS-keystore device-session storage — on web it is browser storage; a
  hardware pilot should run POS/KDS as desktop/mobile builds.
- Cash drawer kick, barcode scanners: out of scope so far.

## 7. Requires production deployment / security sign-off

- **Human RLS/security sign-off** (AGENTS.md gate) before ANY real tenant
  data — this is a hard gate, still outstanding.
- A deployed stable domain (removes the local port/pairing caveat), TLS,
  backups/ops per OPERATIONS_AND_RECOVERY.md.
- Rate limiting on pairing/PIN endpoints; PIN/device session expiry policy
  (Q-009); platform-admin MFA.
- Codex independent review + human approval of this branch (per the agent
  workflow) before merge.

## 8. Verdict

**Ready for a supervised, local restaurant DEMO/pilot-foundation**: the whole
owner → menu/tables/devices/staff → POS (modifiers, tables, auto-send) → KDS
(columns, shared numbers) → cash receipt → summary loop runs for real, in
Arabic, in shekels, with no fake success anywhere. **Not ready for a paid
production deployment** (sections 3, 6, 7).
