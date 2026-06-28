# M6 Final QA — Isolation Run Guide (RF-121)

> **STATUS — ADVISORY / QA RUNBOOK (M6).** This is a practical, repeatable QA
> procedure for verifying the M6 app surfaces **in isolation** and confirming the
> **demo-vs-real boundaries** are honest. It is **not** frozen canon and it does
> not redefine any owning document. The hard merge gate is owned by
> [TESTING_STRATEGY.md](TESTING_STRATEGY.md); tenant-isolation cases by
> [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md); incident/severity
> procedure by [RUNBOOKS.md](RUNBOOKS.md); the demo setup by
> [M5_DEMO_RUN_GUIDE.md](M5_DEMO_RUN_GUIDE.md); the real-integration direction by
> [M6_REAL_PRODUCT_INTEGRATION_PLAN.md](M6_REAL_PRODUCT_INTEGRATION_PLAN.md).
> This guide **references** those; it never overrides them.
>
> Status markers used below: **READY** (implemented + tested), **SIMULATED-LOCAL**
> (logic exists, in-memory/demo only — no live backend), **NOT IMPLEMENTED —
> human/infra** (needs real deployment/hardware/keys). Money is integer minor
> units everywhere (**DECISION D-007**). Platform admin is read-only
> (**DECISION D-026**). Sync is polling-first, Realtime-as-enhancement-only
> (**DECISION D-010**).

---

## 1. Purpose

Verify each M6 app surface **on its own**, with no dependency on the other apps,
and confirm that:

- every surface **runs in isolation** (one app at a time, no cross-app wiring);
- the **demo / no-backend / no-printer** boundaries are **clearly labelled** and
  honest (nothing claims live data or real hardware that isn't there);
- the automated gate (format / analyze / tests / l10n / guards) is **green**;
- money is integer minor units, the platform-admin surface stays **read-only**,
  and no secrets / raw JSON / UUID walls leak into any UI.

This is a **demo build** QA pass. Real backend, sync activation, hardware
printing and Realtime are **deferred** (see §11). The goal is "is M6 easy to
verify and safe to move forward from", not "is it production-live".

---

## 2. Prerequisites

| Need | Detail |
|---|---|
| Flutter / Dart | Flutter with Dart `^3.12.0` on PATH (`flutter --version`). |
| Repo path | `C:\Users\saleh\Desktop\ClaudeAi\RestoFlow\RestoFlow` (run commands from this **repo root** unless noted). |
| Clean git tree | `git status --short` prints nothing before you start. |
| Dependencies | This is a **Dart pub workspace** (4 apps + 18 packages; Melos 7 config lives under the `melos:` key in the root `pubspec.yaml`). Run `flutter pub get` **once at the repo root** to resolve all apps/packages. |
| Browser | Google Chrome (all four apps run on the **Flutter web** target). |
| Git Bash (Windows) | The `*.sh` guards need **Git Bash** (`C:\Program Files\Git\bin\bash.exe`). Plain/WSL `bash` may fail on GNU `grep`/`sed`/`tr` differences. `check_l10n.dart` is pure Dart and runs anywhere. |

Demo mode is the **default** (`RESTOFLOW_DEMO_MODE` defaults to `true`), so the
plain run commands below open each app's demo surface with no backend. You can
force it explicitly with `--dart-define=RESTOFLOW_DEMO_MODE=true`.

---

## 3. Baseline commands (run once, at the repo root)

```bash
git status --short            # expect: clean (no output)
git branch --show-current     # confirm the branch you intend to QA
git pull --ff-only origin main  # only if you intend to QA latest main
flutter pub get               # resolve the whole workspace

# Whole-gate sanity (details in §9):
dart format --output=none --set-exit-if-changed .
dart analyze apps packages
```

---

## 4. App isolation matrix

Every app runs **independently** — none imports another app, and none needs
another app running. Run each from **its own directory**.

| App | Path | Run (web/Chrome) | Test | Surface that opens | Demo label shown | Backend status |
|---|---|---|---|---|---|---|
| POS | `apps/pos` | `cd apps/pos && flutter run -d chrome` | `flutter test apps/pos` | Menu + cart POS screen (order build → send → pay → receipt/print preview) | `posShiftDemoNote` "Demo shift — not synced"; receipt notes (see §5) | **SIMULATED-LOCAL** — real outbox/idempotency shape, demo org/branch/device; no live session |
| KDS | `apps/kds` | `cd apps/kds && flutter run -d chrome` | `flutter test apps/kds` | Kitchen order board (status columns + ticket actions + ticket print preview) | `kdsDemoFeedBanner` "Demo kitchen feed — not synced to a backend" | **SIMULATED-LOCAL** — demo fixture tickets; not synced to live POS/backend |
| Owner dashboard | `apps/dashboard` | `cd apps/dashboard && flutter run -d chrome` | `flutter test apps/dashboard` | Owner reports overview (KPIs, daily + payment summary, branches, top items, recent orders) | `dashboardDemoReportsNotice` (see §7) | **SIMULATED-LOCAL** — computed demo dataset; RF-075/092 views exist but not wired |
| Platform admin | `apps/admin` | `cd apps/admin && flutter run -d chrome` | `flutter test apps/admin` | Platform overview (KPIs, organizations, branch health, recent activity) | `adminDemoDataNotice` (see §8) | **SIMULATED-LOCAL** — computed demo dataset; RF-091 RPCs exist but not wired |

> Each app gates entry through the shared auth gate
> (`AppSurface.pos/kds/dashboard/admin`); in demo mode the gate is bypassed and
> the demo surface renders directly. The admin surface, in auth mode, is
> entered **only** by `is_platform_admin == true` (**DECISION D-026**).

---

## 5. POS QA checklist (`apps/pos`)

Run `cd apps/pos && flutter run -d chrome`.

| # | Check | Expected |
|---|---|---|
| 1 | Order type | Toggle **Dine-in / Takeaway** in the cart; the chip updates. |
| 2 | Dine-in table assignment | With Dine-in selected, open the table picker (floor-map layout), pick a free table; occupied/blocked tiles are disabled; the selection shows on the cart and (after submit) on the confirmation. Switching back to Takeaway clears the table. |
| 3 | Send Order | Add an item, tap **Send order**; a submitted-order confirmation appears with an order number (e.g. `DEMO-0001`). |
| 4 | Outbox / sync status | The submit flow uses the real **outbox + idempotency** shape (device_id + local_operation_id) but operates **demo-local** — there is no live backend round-trip. No "synced to server" claim should appear. |
| 5 | Cash payment | Tap **Pay (cash)**, choose a quick-cash amount (e.g. exact), confirm; change due is computed in integer minor units. |
| 6 | Receipt preview | After payment, open the receipt preview: restaurant name, **Paid** chip, receipt no. (`PROV-0001`), order no., type/table, paid-at, itemised lines (`qty× name`), total, cash, change, payment method. |
| 7 | Browser print preview | In the receipt preview tap **Print**: a **new isolated browser window** opens containing **only the receipt** and auto-prints — the POS menu/app behind the modal is **not** printed (RF-118 isolation). |
| 8 | Language selector EN/AR/HE | The app bar has a **language selector** (translate icon). Switch to العربية / עברית / English; the whole app re-localizes immediately. |
| 9 | RTL behaviour | Arabic/Hebrew flip the layout to **right-to-left**; English is left-to-right. |
| 10 | Demo / no-backend / no-printer labels | `posShiftDemoNote` "Demo shift — not synced"; `posReceiptProvisionalNote` "Provisional — reconciled to a server receipt on sync"; `posReceiptDemoNote` "Demo receipt — no printer connected"; `printPreviewAction` "Print preview". No real-printer or live-backend claim anywhere. |

**POS honesty:** submit/outbox is real in *shape* but demo-local; receipt numbers
are **provisional** (`PROV-<seq>`, reconciled on a future real sync); printing is
a **browser preview** only — no hardware printer / drawer-kick
(**DECISION D-009**, **OPEN QUESTION Q-006/Q-015**).

---

## 6. KDS QA checklist (`apps/kds`)

Run `cd apps/kds && flutter run -d chrome`.

| # | Check | Expected |
|---|---|---|
| 1 | Board columns | The board shows status columns and a demo banner at the top. |
| 2 | Ticket cards | Large, kitchen-readable cards: order number, status chip, order type / table / elapsed time, itemised lines with quantities + modifiers/notes. |
| 3 | Start / Mark ready / Complete / Recall | The single status-gated lifecycle action advances the ticket (New → Start → Mark ready → Complete; Recall where applicable); the card moves/updates. |
| 4 | Ticket print preview | Open a card's **Preview ticket**: a kitchen "paper" with big quantities; money-free (**SECURITY T-003** — kitchen sees no money). |
| 5 | Browser print isolation | Tap **Print** in the ticket preview: a new isolated window opens with **only that ticket** and auto-prints — the KDS board behind the modal is **not** printed. |
| 6 | Language selector EN/AR/HE | The app bar has a **language selector**; switching re-localizes the board immediately. |
| 7 | RTL behaviour | Arabic/Hebrew render right-to-left; English left-to-right. |
| 8 | Demo / not-backend-synced banner | `kdsDemoFeedBanner` "Demo kitchen feed — not synced to a backend" is visible. |

**KDS honesty:** the board is a **demo fixture feed**, seeded in-memory; it does
**not** sync with actual POS-submitted orders. The sync path exists
(polling-first per **DECISION D-010**) but is not activated in the demo.

---

## 7. Owner dashboard QA checklist (`apps/dashboard`)

Run `cd apps/dashboard && flutter run -d chrome`. The Overview tab is the owner
reports surface.

| # | Check | Expected |
|---|---|---|
| 1 | Owner reports overview | "Owner reports" heading + report-day context ("Report day: 2026-06-28") + a "Demo day" pill. |
| 2 | Demo banner | `dashboardDemoReportsNotice` "Demo reports — calculated locally from sample orders, not synced to a backend. Real backend reporting is deferred." |
| 3 | KPI cards (exact RF-119 demo values) | Gross sales **₪626.00**, Net sales (today's sales) **₪620.00**, Orders **7**, Avg. order value **₪88.57**, Cash sales **₪474.00**, Completed **5** (Open: 2), Unpaid orders **2**. |
| 4 | Payment & cash summary | Opening float **₪500.00**, Cash sales **₪474.00**, **Expected in drawer ₪974.00** (= float + cash sales), Counted cash **₪972.50**, **Cash variance −₪1.50**, Last cash payment **₪58.00**, method breakdown **5 · ₪474.00** (cash only). |
| 5 | Top items | Ranked by revenue: **Margherita Pizza ₪218.00** (#1, ×4), then Classic Burger ₪168.00, Caesar Salad ₪114.00, French Fries ₪64.00, Fresh Lemonade ₪56.00. |
| 6 | Recent orders | Newest-first list (order no., time, type, table if dine-in, status, paid/unpaid, total); newest is `O-1009` (cancelled). |
| 7 | Loading / error / empty | Async load via the `OwnerReportsRepository` seam → loading spinner, error+retry, and an empty state are covered (testable via `apps/dashboard/test/dashboard_states_test.dart`). |
| 8 | RTL / device locale | No in-app language selector here — locale follows the **device** and RTL is automatic for ar/he (verified by `apps/dashboard/test/dashboard_rtl_test.dart`). |

**Owner dashboard honesty:** all figures are **computed from a structured demo
dataset** (`apps/dashboard/lib/src/data/`), not a live backend; the frozen
RF-075/RF-092 report views exist server-side but the client does not query them.

---

## 8. Platform admin QA checklist (`apps/admin`)

Run `cd apps/admin && flutter run -d chrome`.

| # | Check | Expected |
|---|---|---|
| 1 | Platform overview | "Platform overview" title + "As of 2026-06-28" + a "Demo data" pill. |
| 2 | Demo banner | `adminDemoDataNotice` "Demo platform data — computed locally, not synced to a backend. Real platform admin data wiring is deferred." |
| 3 | KPI cards (exact RF-120 demo values) | Organizations **3** (Active: 2), Restaurants **4**, Branches **6**, Active branches **5**, Devices **10**, Open alerts **2**, Orders today **215**. |
| 4 | Organizations list | Sorted by name: Bistro Group (2 restaurants · 3 branches · pro), Cafe Noor (1 · 2 · standard), Pizza Plaza (1 · 1 · trial, **suspended**). |
| 5 | Branch health warnings | Six branches; exactly **two** "Needs attention" chips — **Noor Airport** (inactive branch) and **Plaza HQ** (active branch under a suspended org). |
| 6 | Recent activity | Newest-first feed; newest event is `sync_warning` (Pizza Plaza · Plaza HQ device offline). |
| 7 | Auth / platform-admin gate | In demo mode the overview renders directly. In auth mode, entry is **only** for `is_platform_admin == true` (**DECISION D-026**); a tenant role (even org_owner) is denied (`authWrongRole`). The surface is **read-only** — no grant/revoke/impersonation/mutation. |
| 8 | RTL / device locale | No in-app language selector — locale follows the **device**, RTL automatic for ar/he (verified by `apps/admin/test/platform_admin_rtl_test.dart`). |

**Platform admin honesty:** all figures are **computed from a structured demo
dataset** (`apps/admin/lib/src/data/`); the frozen RF-091 platform-admin RPCs
(`platform_admin_organization_overview` / `recent_audit`) exist server-side but
are not invoked. Counts only — **no money** on this surface.

---

## 9. Automated validation (the gate)

Run from the **repo root**. All must pass (green) before sign-off.

```bash
dart format --output=none --set-exit-if-changed .   # formatting
dart analyze apps packages                          # static analysis (or: melos analyze)

flutter test apps/pos
flutter test apps/kds
flutter test apps/dashboard
flutter test apps/admin
flutter test packages/l10n

dart run tools/check_l10n.dart                      # ARB + committed gen-l10n parity (pure Dart)
bash tools/check_no_hardcoded_strings.sh            # no Text('literal') in app shells
bash tools/check_no_float_money.sh                  # no floating-point money (D-007)
bash tools/check_secrets.sh                         # no committable secrets

git diff --check                                    # no whitespace/conflict markers
```

Expected passing messages:

- `check_l10n.dart` → "OK: l10n ARB + committed gen-l10n output are present and structurally consistent (Flutter-free check)."
- `check_no_hardcoded_strings.sh` → "OK: no hardcoded user-facing strings in scaffolded app shells …"
- `check_no_float_money.sh` → "OK: no floating-point money modeling found under apps/ and packages/ …"
- `check_secrets.sh` → "OK: no committable secrets detected …"

**Windows note:** the three `*.sh` guards require **Git Bash**
(`C:\Program Files\Git\bin\bash.exe`). Plain `bash`/WSL may fail on GNU
`grep`/`sed`/`tr` differences. `check_l10n.dart` is pure Dart and runs anywhere.
`check_secrets.sh` can take a minute or two (it scans tracked + non-ignored
files) — run it on its own if a combined command times out.

> To regenerate l10n after editing an ARB: flip `generate: false` → `true` in
> `packages/l10n/pubspec.yaml`, run `flutter gen-l10n` from `packages/l10n`,
> then revert the flag. The generated output is **committed**; CI never runs
> codegen.

---

## 10. Manual QA pass/fail table

Copy this table per run and fill it in.

| Area | Check | Expected result | Pass/Fail | Notes |
|---|---|---|---|---|
| POS | Order type + dine-in table | Type toggles; table picker assigns/clears | | |
| POS | Send order | Submitted-order confirmation w/ order no. | | |
| POS | Cash payment + change | Integer-minor change computed | | |
| POS | Receipt + browser print isolation | Only the receipt prints, not the app | | |
| POS | Language selector + RTL | EN/AR/HE switch; ar/he go RTL | | |
| POS | Demo labels | "Demo shift", "Provisional…", "Demo receipt — no printer connected" | | |
| KDS | Board + ticket actions | Lifecycle actions advance tickets | | |
| KDS | Ticket print isolation | Only the ticket prints | | |
| KDS | Language selector + RTL | EN/AR/HE switch; ar/he go RTL | | |
| KDS | Demo banner | "Demo kitchen feed — not synced to a backend" | | |
| Dashboard | KPI values | Gross ₪626.00 / Net ₪620.00 / 7 / ₪88.57 / Cash ₪474.00 | | |
| Dashboard | Drawer math | Expected ₪974.00, variance −₪1.50 | | |
| Dashboard | Top item | Margherita Pizza ₪218.00 (#1) | | |
| Dashboard | Demo banner + RTL | Demo-reports banner; ar/he RTL (device locale) | | |
| Admin | KPI values | 3 / 4 / 6 / 5 / 10 / 2 / 215 | | |
| Admin | Orgs + branch health | Pizza Plaza suspended; 2 "Needs attention" | | |
| Admin | Recent activity | Newest = sync_warning | | |
| Admin | Read-only + gate | No mutations; platform-admin-only entry | | |
| Admin | Demo banner + RTL | Demo-platform banner; ar/he RTL (device locale) | | |
| Gate | Automated validation (§9) | All green | | |

---

## 11. Demo / backend honesty table

| Surface | Honest limitation (what is real vs demo) | Status |
|---|---|---|
| POS submit / outbox | Real outbox + idempotency **shape** (device_id + local_operation_id), but runs in a hardcoded **demo org / branch / device** context — no live authenticated session/round-trip. | SIMULATED-LOCAL |
| POS payment / receipt | Cash-only; receipt numbers are **provisional** (`PROV-<seq>`) assigned locally; server-authoritative numbering (**DECISION D-021**) deferred. | SIMULATED-LOCAL |
| POS / KDS printing | **Browser preview only** (isolated `window.print()`); **no** hardware printer, network/USB/Bluetooth, or drawer-kick. | NOT IMPLEMENTED — human/infra |
| KDS feed | **Demo fixture tickets** seeded in-memory; **not** synced to actual POS orders. Polling-first sync path exists (**D-010**) but is not activated. | SIMULATED-LOCAL |
| Owner reports | Computed from a **structured demo dataset**; RF-075/092 report views exist server-side but are not queried. | SIMULATED-LOCAL |
| Platform admin | Computed from a **structured demo dataset**; RF-091 platform-admin RPCs exist server-side but are not invoked. **Read-only** (**D-026**). | SIMULATED-LOCAL |
| Realtime | Not used by any M6 surface; sync is **polling-first** (**DECISION D-010**), Realtime is enhancement-only. | NOT IMPLEMENTED — human/infra |
| Real backend wiring | Live multi-tenant session, real sync activation, report-view queries, and platform-admin RPC calls are **deferred** to a later integration ticket (see [M6_REAL_PRODUCT_INTEGRATION_PLAN.md](M6_REAL_PRODUCT_INTEGRATION_PLAN.md)). | HUMAN DECISION |

---

## 12. Isolation / security checks

| Check | Expected | Why |
|---|---|---|
| Apps run independently | Each app starts and is fully usable without any other app running; no app imports another app's code. | True isolation; admin-local widgets mirror (not import) dashboard widgets. |
| No secrets in UI/code | No API keys / tokens / service-role creds in any screen or demo dataset. | `check_secrets.sh`; no service-role key in clients (**DECISION D-011**). |
| No raw JSON / UUID wall | Every surface renders friendly cards/lists/chips — no debug payloads, no raw UUID dumps. | Product-grade UI; QA reject criterion. |
| No false real-backend claim | Every demo surface carries an honest "demo / not synced / deferred" label; nothing claims live data or real printing. | Honesty requirement (this guide §11). |
| Platform admin read-only | No grant/revoke/impersonation/mutation/destructive action on the admin surface. | **DECISION D-026**; admin is a separate, audited, read path. |
| Money integer minor units | All money is integer `_minor`; no floating-point anywhere; KDS is money-free. | **DECISION D-007**; `check_no_float_money.sh`; **SECURITY T-003**. |
| Language / RTL visible where selectors exist | POS + KDS expose an EN/AR/HE selector; dashboard + admin follow device locale; ar/he render RTL on all four. | **DECISION D-014** (ar/he/en, RTL+LTR). |

> Tenant-isolation correctness (RLS, cross-tenant read/write) is owned and
> gated by [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) and
> [TESTING_STRATEGY.md](TESTING_STRATEGY.md); the mandatory human RLS sign-off
> (**RISK R-003**, CRITICAL) is a separate go-live gate and is **out of scope**
> for this demo-build isolation pass.

---

## 13. Sign-off

A run is **PASS** when: every app opened and behaved per §5–§8, every demo label
in §11 was present and honest, the §10 table has no Fail rows, and the §9 gate is
green. Record the date, the commit hash QA'd, and any Fail-row notes. Anything
that looks like a live-backend or real-printer claim, a secret, a raw JSON/UUID
wall, or a cross-app run dependency is a **defect** — file it (severity per
[RUNBOOKS.md](RUNBOOKS.md)) before moving forward.
