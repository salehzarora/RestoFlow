# RestoFlow — Local Runbook (Real MVP Flow)

> How to run the whole product locally, for real: local Supabase backend, owner
> dashboard, POS, and KDS. This is written for a manual tester clicking through
> the screens — it says what you will actually see.
>
> This runbook is developer/pilot documentation. The authoritative architecture
> lives in `docs/` (see [ARCHITECTURE.md](ARCHITECTURE.md)); security rules in
> [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md). No secrets in
> this file — the local publishable key is printed by the Supabase CLI on your
> machine.

---

## Demo mode vs Real mode

- **Demo mode** is the default (`RESTOFLOW_DEMO_MODE` defaults to `true`). No
  backend, no account, sample data everywhere — safe to explore. Every
  demo-backed page carries a **demo banner**, and the dashboard header shows a
  blue **Demo** pill.
- **Real mode** (`--dart-define=RESTOFLOW_DEMO_MODE=false` + the Supabase URL
  and key) talks to the real local backend: real accounts, real rows, real
  RLS. The dashboard header shows a green **Real** pill. Nothing demo is ever
  shown as if it were real: pages that are not connected yet say so instead of
  showing sample data.

## About the keys (important)

`supabase start` prints two keys. The apps use ONLY the **anon / publishable**
key — the one that is safe to ship in a client. **Never use the
`service_role` / secret key in any app** (DECISION D-011); the apps reject
service-role-looking keys at startup. If a page ever asks you for a key, that
is a bug — only the launch command takes it.

## 0. Prerequisites

- Flutter (repo CI pins 3.44.2 stable) + Chrome.
- Supabase CLI (repo CI pins 2.107.0) + Docker Desktop running.
- One-time workspace setup from the repo root:

```sh
flutter pub get
dart run melos bootstrap
```

## 1. Start Supabase locally

From the repo root:

```sh
supabase start
```

- Prints the local **API URL** (default `http://127.0.0.1:54321`) and the
  **anon key** (labelled `anon` / publishable). You need both for real mode.
- The checked-in `supabase/config.toml` already enables **anonymous
  sign-ins** — POS/KDS devices sign themselves in anonymously to reach the
  pairing backend (no personal account ever exists on a device). A hosted
  project needs the same Auth toggle.

Useful:

```sh
supabase status          # re-print URLs + keys
supabase stop            # stop the stack (data preserved)
```

## 2. Open Supabase Studio

Studio runs at **http://127.0.0.1:54323** (see `supabase/config.toml`). Use it
to inspect tables (RLS still applies to app roles — Studio uses a privileged
local connection). Normal manual testing never needs Studio: the dashboard can
now do everything the flow below requires.

## 3. Reset the local database

Re-applies every migration to a clean local DB:

```sh
supabase db reset
```

Run the backend test suite (pgTAP, includes the tenant-isolation harness):

```sh
supabase test db        # requires a prior `supabase db reset`
```

> `supabase test db` does NOT apply pending migrations — always `db reset`
> first after changing `supabase/migrations/`.

## 4. Run the apps

### Demo / preview launch (no backend needed)

```sh
# Dashboard (owner/manager)
cd apps/dashboard && flutter run -d chrome

# POS (cashier)
cd apps/pos && flutter run -d chrome

# KDS (kitchen)
cd apps/kds && flutter run -d chrome
```

### Real Local mode — use the stable-port scripts (recommended)

From the repo root, double-click or run:

```bat
_run_dashboard_real.bat   REM Dashboard on http://localhost:57026
_run_pos_real.bat         REM POS       on http://localhost:52096
_run_kds_real.bat         REM KDS       on http://localhost:49622
```

**Why fixed ports matter locally:** the browser scopes storage — the owner's
signed-in session AND a device's pairing — per **origin** (scheme + host +
**port**). Plain `flutter run` picks a *random* port each time, so the next
run looks like a wiped sign-in / lost pairing and the POS/KDS would ask for a
new code. The scripts pin one port per app so pairing survives restarts. A
deployed build on a stable domain never has this problem. The scripts default
to the local Supabase URL and the CLI's local **publishable** key (override
with the `RESTOFLOW_SUPABASE_URL` / `RESTOFLOW_SUPABASE_ANON_KEY` env vars if
yours differ — never a secret key).

### Real Local mode — manual command

Pass the three defines (URL + anon key from `supabase status`) and keep a
STABLE `--web-port` (see above):

```sh
# Dashboard — real local
cd apps/dashboard
flutter run -d chrome --web-port=57026 \
  --dart-define=RESTOFLOW_DEMO_MODE=false \
  --dart-define=RESTOFLOW_SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=RESTOFLOW_SUPABASE_ANON_KEY=<anon key>

# POS — real local (same three defines)
cd apps/pos
flutter run -d chrome --web-port=52096 \
  --dart-define=RESTOFLOW_DEMO_MODE=false \
  --dart-define=RESTOFLOW_SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=RESTOFLOW_SUPABASE_ANON_KEY=<anon key>

# KDS — real local (same three defines)
cd apps/kds
flutter run -d chrome --web-port=49622 \
  --dart-define=RESTOFLOW_DEMO_MODE=false \
  --dart-define=RESTOFLOW_SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=RESTOFLOW_SUPABASE_ANON_KEY=<anon key>
```

What you see when something is wrong (never a crash, never fake data, never a
misleading "Account access denied"):

- Missing/invalid defines → a **"Real mode is not configured"** help page
  listing these exact defines.
- POS/KDS with anonymous sign-ins disabled on the backend → a **"Device
  sign-in unavailable"** page stating "Anonymous device sign-in is disabled or
  Supabase auth is not configured." and showing the config toggle to flip.
- POS/KDS configured correctly but not yet paired → the **pairing screen**
  (that is the normal first-run state; see step 4 of the checklist).

## 5. First 15 minutes — the on-screen checklist

The dashboard's **Overview** shows a **Setup** panel in real mode with four
counters (Menu items · Devices · Printers · Staff PINs) and a banner for each
missing step, each with a button that opens the right tab. Following the
banners top-to-bottom IS the setup flow.

The short version, in order:

1. Add a menu category + item first (Menu tab).
2. Add POS and KDS devices and issue pairing codes (Devices tab).
3. Pair the POS and KDS apps with those codes.
4. If POS/KDS says **"No staff PINs yet"** — go Dashboard → Staff and create
   a staff member with a PIN (cashier for POS, kitchen staff for KDS).
5. Return to the POS/KDS and tap **Try again**.
6. Sign in with the PIN and submit an order.

Written out in full:

1. **Sign up** (dashboard, real mode): email + password (local auth has email
   confirmation disabled, so sign-up signs you straight in). The onboarding
   screen asks for your **restaurant name** (+ optional branch name); submitting
   creates organization → restaurant → branch → a default station → your
   `org_owner` membership. You land in the shell: your restaurant · branch in
   the header, a green **Real** pill, and the Setup checklist below.
2. **Add your first menu item** (Menu tab): **Add category** (e.g. "Mains"),
   then **Add item** — name, price (entered in your currency, stored as
   integer minor units), optional description, enabled. **Menu items are what
   the POS sells**: a POS with no menu items has nothing to ring up. The menu
   you build here is exactly what the paired POS downloads.
3. **Create devices** (Devices tab): **Create device** for the POS (type
   POS) and one for the kitchen display (type KDS). A "device" is one
   physical screen — the cashier's till, the kitchen's display. On each card,
   **Issue code** shows a one-time pairing code **once** (~15 min expiry; the
   backend stores only its hash).
4. **Pair the POS and KDS**: run each app in real mode (commands above). The
   app shows its pairing screen — type the matching code from step 3. Pairing
   sticks across restarts (a device session in browser/secure storage,
   type-checked per surface: a KDS code/session can never unlock a POS).
   **Revoke** on a device card ends its access; the device falls back to the
   pairing screen.
   > A freshly paired device with no staff yet shows **"No staff PINs yet"**
   > with the setup steps — that is the normal state, not an error. Do step 5,
   > then tap **Try again** on the device.
5. **Create staff + PIN** (Staff tab): **Add staff member** (name + role:
   cashier / kitchen staff / manager), then **Set PIN** (4–8 digits, entered
   obscured; the backend stores a bcrypt hash only; wrong-PIN attempts are
   rate-limited with lockout). The paired POS/KDS PIN screens list these
   people for sign-in: on the POS a **cashier or manager** PIN signs in; on
   the KDS a **kitchen staff or manager** PIN. Back on the device, tap
   **Try again** and the new names appear.
6. **Add a printer** (Printers tab, optional for the order loop): name, role
   (receipt / kitchen), connection:
   - **Network / Wi-Fi**: enter the printer's **IP address**; the port hides
     under **Advanced** (default 9100).
   - **Bluetooth**: discovery is **not supported in the web app** — the dialog
     says so and saves the configuration only.
   - **USB**: needs the desktop/native printer adapter — the dialog says so
     and saves the configuration only.
   The dialog always states that **this build saves configuration only —
   nothing is printed yet**. Route the printer to a station if you want the
   routing recorded.
7. **Run the order loop**: on the POS, sign in with the cashier PIN (a shift
   auto-opens, float 0), tap menu items into the cart, submit, take cash — the
   server assigns the receipt number. On the KDS, sign in with the kitchen
   PIN: the ticket appears on the live board; Acknowledge → Start → Ready →
   Bump pushes the status back. On the dashboard Overview, **Refresh** the
   sales summary to see today's orders and gross.

When every step is done the Setup panel shows a green "This branch is ready"
banner.

## 6. What each dashboard tab really is (real mode)

- **Overview** — real `sales_summary` (orders today, completed payments,
  gross, 7-day series) + the Setup checklist. Manual refresh; realtime is an
  enhancement, never a dependency.
- **Menu** — REAL menu management (`list_menu` + `menu_upsert_*`): categories,
  items, prices (integer minor units), enable/disable, soft-delete. What you
  save here is what the POS sells.
- **Devices** — real device provisioning: create, issue one-time pairing
  codes, revoke. Devices pair themselves with the code (no manager-side
  "activate" button — that would be fake).
- **Printers** — real configuration storage + station routing. No printing
  happens in this build, and every screen involved says so.
- **Staff** — real staff + PIN provisioning (bcrypt server-side).
- **Users** — NOT connected yet: real mode shows an honest "User management
  not connected yet" page (there is no member read API). No sample people.
- **Settings** — read-only real workspace values (organization, restaurant,
  branch, currency, your role) with an honest "editing is not connected yet"
  notice. No Save button exists because saving is not wired.

## 7. Real order loop — what happens underneath

1. POS (real, paired, PIN session as cashier): the menu comes from
   `public.pos_menu` over the live `menu_items` rows you created in the Menu
   tab. Orders go through the offline outbox → `public.sync_push`
   (`order.submit`) with an idempotency key (device + local operation id,
   D-022). Cash payment uses `payment.create`; the server assigns the receipt
   number. `record_payment` REQUIRES an open shift (RF-055): the POS opens one
   automatically (opening float 0) right after the staff PIN sign-in. To
   **close/reconcile** it, open the POS **⋮ device menu → Close shift** (RF-113):
   enter the counted cash and the panel shows the server-computed **expected vs
   counted vs difference** (over/short) in ₪. After a close the POS **returns to
   PIN sign-in** (a cashier can't sell without a shift; the next sign-in opens a
   fresh one). On a **browser refresh** the POS re-reads the still-open shift via
   `sync_pull` and Close shift keeps working; if it genuinely can't be restored it
   shows an honest "sign in again" state rather than a misleading "no open shift".
   A real opening-float entry (non-zero) is still deferred.
   **Owner switch (RF-113):** the visible Close-shift workflow is a per-branch
   policy the owner controls from **Dashboard → Settings → "Shift reconciliation
   (POS)"** (`branches.pos_shift_close_enabled`, default **on**; owner-only —
   managers/cashiers see it read-only, and the POS device can never change it).
   When it's **off** the POS simply **hides** the ⋮ Close-shift entry; payments
   are unaffected because the server's own open-shift requirement (RF-055) is a
   separate, always-on rule. The POS reads the flag token-proven via
   `public.get_device_pos_shift_close_enabled`; the Dashboard reads/writes it via
   `public.get_branch_pos_shift_close_enabled` / `set_branch_pos_shift_close_enabled`
   (owner gate = rank ≥ restaurant_owner, same as the other branch settings).
2. KDS (real, paired, PIN session as kitchen staff): the board polls
   `public.sync_pull` — financial entities (payments/shifts/cash drawer) are
   **never pulled** for kitchen staff, and the board renders no money (T-003).
   (Order rows do carry integer totals in the wire payload today — a
   pre-existing RF-057 shape; nothing money-typed is displayed or stored.)
   Advancing a ticket (accept → preparing → ready → bump/served) pushes
   `order.status` through the same sync pipeline and persists. **Recall** is
   demo-only (the backend is forward-only), so the live board hides it; if
   the session expires (~8h) the board offers **Sign in again**.
3. Dashboard → Overview shows the real sales summary with a manual
   **Refresh**.

## 7b. Platform admin app (what it is, who it is for)

RestoFlow has FOUR apps with different audiences:

| App | Who | Port (local real mode) |
|---|---|---|
| Dashboard | restaurant owner / manager | 57026 (`_run_dashboard_real.bat`) |
| POS | cashier (paired device + staff PIN) | 52096 (`_run_pos_real.bat`) |
| KDS | kitchen (paired device + staff PIN) | 49622 (`_run_kds_real.bat`) |
| **Admin** | **RestoFlow platform operator only** | 57126 (`_run_admin_real.bat`) |

The Admin app is the **platform** administration panel (all organizations,
platform health, audit) — it is NOT the restaurant owner's panel, and normal
restaurant accounts can never use it:

- Entry requires `is_platform_admin == true` on the signed-in account
  (DECISION D-026 — platform admin is a separate, audited grant, never a
  tenant role; owners/managers are NOT platform admins and must not be made
  platform admins to "fix" access).
- Live platform data additionally requires, server-side (RF-091): an ACTIVE
  `platform_admin_grants` row **and** an MFA (aal2) session **and** a
  non-empty audited reason on every read. There is deliberately NO
  grant/revoke RPC and no self-service path.
- A visitor without that access now sees an explainer screen (Arabic-first):
  "هذه لوحة إدارة المنصة، وليست لوحة صاحب المطعم." /
  "استخدم Dashboard لإدارة المطعم." — with an Open-Dashboard action and the
  local Dashboard URL. This replaces the old dead-end "Account access denied".

**Local, dev-only platform-admin provisioning** (safe flow — no bypass, no
service-role key; production grants are an operator/DBA action):

1. Sign up once in the Dashboard real mode (this creates the linked
   `app_users` row via `create_organization`).
2. In Supabase Studio (http://127.0.0.1:54323 → SQL editor) grant yourself:

   ```sql
   insert into platform_admin_grants (app_user_id, granted_by)
   select id, id from app_users where email = 'you@example.test';
   ```

3. The gate now admits you (`is_platform_admin = true`), but live reads still
   need **MFA aal2**: local TOTP is enabled in `supabase/config.toml`
   (`[auth.mfa.totp]`), and the admin app has no MFA enrolment UI yet — so
   without an aal2 session you will see the honest "Platform admin access
   denied" data state (grant + MFA required). That state is correct, not a
   bug.

Note the admin app has no sign-in screen of its own in this build; it reads
the session state via `get_my_context`. Missing Supabase config shows the
same "Real mode is not configured" help page as the other apps.

## 7c. POS/KDS device settings + auto-print (for the staff on the device)

The POS and KDS app bars carry a **⋮ device menu** → **Device settings**. This
is an **operational device panel for the STAFF on the already-paired device**
— NOT an owner/admin screen. It never exposes owner data, never touches other
devices/branches, and the KDS panel is money-free (T-003). It shows:

- **App type** (Cashier POS / Kitchen display KDS), **restaurant / branch**,
  **device label**, **pairing** status, and **staff session** status.
- **Printers** assigned to *this device's branch*, read through a token-proven
  RPC (`get_device_printer_assignments`) — the device proves itself with its
  own session token; the server returns only safe metadata (name, role,
  connection type, paper width, enabled/disabled) and **derives the branch
  from the session**. A POS sees only **receipt** printers; a KDS sees only
  **kitchen** printers. No secrets (LAN host/port) are ever sent to the device.
- **Auto-print** toggles (see below).
- **Refresh connection** and **Unpair this device** (see below).

**Printer configuration lives in the Dashboard.** The owner/manager configures
printers and station routes in **Dashboard → Printers**; the device panel only
*reads* the assignment for its branch. If the device shows **"No printer
assigned. Ask a manager to configure it in Dashboard → Printers."**, add one in
the Dashboard.

**Physical printing requires a print bridge / native transport.** This web
build has **no ESC/POS hardware transport**. So every printer shows
**"Configured only — print bridge required."** and the panel states plainly:
*"Printing requires a print bridge/native app. This build can save config and
create/preview print jobs."* Print jobs are **prepared/previewed**, never
reported as physically printed. A job status is one of: **No printer
configured**, **Print job prepared — physical printing requires print bridge**,
**Printed** (only ever shown when a real transport confirms — unreachable in
this build), or **Print failed** (which never affects the order/ticket).

**Auto-print triggers** (per-device, stored locally per browser/device — no
owner login, no secrets):

- **POS — auto-print receipt after payment**: after a payment SUCCEEDS, the POS
  prepares a customer-receipt print job (order number, table, items, modifier
  quantities, item notes, totals/payment/change). A failed submit/payment never
  prints. Default ON when an enabled receipt printer is assigned; disabled with
  the reason when none is.
- **KDS — auto-print kitchen ticket on acknowledge**: when kitchen staff tap
  **Acknowledge / استلام** and the status update SUCCEEDS, the KDS prepares a
  kitchen-ticket print job (order code, table, station, items ×N, modifier
  quantities, item/order notes — **no money**). It fires on the tap only (never
  on a poll refresh) and is idempotent per order (no double-print on re-tap or
  reload). Default ON when an enabled kitchen printer is assigned. Print-on-
  first-seen is deliberately not offered (it could storm the printer on reload).

**Refresh + Unpair (staff can reconnect without an owner login):**

- **Refresh connection** re-reads the device's printer assignments (use it
  after a manager changes the Dashboard config).
- **Unpair this device** shows a warning, then clears **this device's** local
  session (best-effort server self-revoke via the existing
  `revoke_device_session`, then the secure-store secret is cleared) and returns
  the app to the **pairing screen**. It only appears on a real paired device,
  and is a device-local action — it never revokes other devices or touches
  owner/admin state. To use the device again, pair it with a fresh enrollment
  code from **Dashboard → Devices**.

## 7d. Print bridge, users/settings, taxes/discounts/tenders (RF-115/116/117)

The "ops demo bundle" — three connected capabilities for the supervised local demo.
None of them fakes success: each shows the true backend/hardware result.

### Print bridge (RF-115) — real local printing, honestly

The web app cannot open a raw ESC/POS socket, so physical printing goes through a
**local companion bridge**. A small reference bridge ships in `tools/print_bridge/`:

```sh
cd tools/print_bridge && dart pub get
dart run print_bridge                                   # DEMO SINK — accepts jobs, prints nothing
dart run print_bridge --target receipt=192.0.2.10:9100  # real RAW/TCP 9100 printer
```

Then launch the POS/KDS pointed at the **loopback** bridge only:

```sh
flutter run -d chrome --dart-define=RESTOFLOW_PRINT_BRIDGE_URL=http://127.0.0.1:8787
```

- The bridge binds **127.0.0.1 only**; the app's bridge URL is guarded to loopback
  (a non-loopback URL is refused, mirroring the e2e local-only guard). The printer's
  LAN target lives ONLY in the bridge's local config — the app/server never learn it
  (the device printer read still omits `connection_config`).
- **Honest statuses**: a receipt/ticket job is `prepared` (no bridge) →
  `sent to printer` (the bridge confirmed it wrote the bytes to the printer) →
  `bridge unavailable` / `failed` with a safe reason. There is **no "printed &
  confirmed" state**: ESC/POS over a socket has no paper-level acknowledgement, so the
  strongest truthful terminal state is "sent to the printer". A **demo sink** bridge
  says so and stays `prepared` (it reached no hardware). The ⋮ device-settings sheet
  shows a live **bridge status** row; a failed/unavailable job gets a **Retry** button.
- POS receipt carries money (totals / tender / change); the **KDS kitchen ticket stays
  money-free** (code, table, station, items, modifier ×N, notes). The bridge is **off by
  default** — with no `--dart-define` the apps behave exactly as before (prepared-only).

### Users management (RF-116)

Dashboard → **Users** is real in real mode: it lists the organisation's members
(`list_members`, owner/manager+), shows each role/status, lets an owner **change a
role** (`update_role`) or **revoke** a member (`revoke_membership` — sets the membership
revoked and terminates any linked staff PIN). Server-enforced: you can only act on
members you strictly outrank, never on yourself, and **never** platform-admin. A
role/revoke you are not allowed to make returns an honest "permission denied", not a
fake success. **Inviting brand-new accounts is intentionally not built** (there is no
client email→account lookup) — the grant/invite affordance is hidden in real mode.
Demo mode keeps its labelled sample people.

### Settings management (RF-116)

Dashboard → **Settings** now has real editable fields for an owner (branch/restaurant
display name, receipt-number prefix) written via the existing settings RPCs, alongside
the RF-113 shift-close toggle and the RF-117 tax control below. Every field has a real
persisted backend path and an honest saved/denied/failed result — **no fake Save
button**. **Currency stays locked to ILS/₪** (shown read-only, no selector). Fields not
readable server-side (address/receipt-prefix) start blank; a blank leaves the stored
value unchanged.

### Taxes, discounts, non-cash tenders (RF-117)

- **Tax** is a per-branch owner setting (Dashboard → Settings): enable + a rate in basis
  points, **default OFF** (no jurisdiction is frozen — Q-001/Q-002, so no hard-coded
  rate). When enabled, the POS reads it (token-proven), shows a tax line on the cart and
  receipt, and includes the integer tax in the order total (exclusive / added-on-top;
  round-half-away, integer minor units). The server validates the total is internally
  consistent. *Follow-up (documented): the server does not yet re-derive the tax rate
  inside `submit_order`; the demo computes it client-side from the owner's setting.*
- **Discounts** — the POS confirmation screen (before payment) has an **order-level
  discount** (fixed ₪ or %, with a required reason). It is applied through the
  server-authoritative `apply_discount` RPC (recomputes totals from snapshots, clamps to
  the subtotal, audits) and is **authorised**: a cashier without the discount permission
  gets an honest "ask a manager", never a fake local discount. The payment then charges
  the server-recomputed total.
- **Non-cash tenders** — the payment sheet has a **tender selector**: Cash / Card / Bit /
  External. Card/Bit/External are **"record external tender" only** — RestoFlow processes
  no card charge and says so ("no real charge"); they record the exact amount with no
  change. **Only cash affects the shift's expected drawer cash** — non-cash never inflates
  it (enforced server-side; `close_shift` counts cash tenders only). The receipt shows the
  tender type. Void/refund of a completed payment remains out of scope (D-023).

## 8. Known limitations (honest list)

- **Printing hardware**: a real **local bridge** now exists (RF-115, §7d) — network
  RAW/TCP 9100 works through it; jobs report honest `sent to printer` / `failed`
  statuses, never a confirmed physical print (ESC/POS has no paper ack). The bridge is
  off by default; **Bluetooth/USB transports are still not installed** (Q-006/Q-015,
  human-gated), and there is no durable offline print spool (that is RF-114).
- **Users tab**: real in real mode (RF-116) — list / change-role / revoke. **Inviting
  brand-new accounts is not built** (no client email→account lookup); grant is hidden.
- **Settings tab**: real editable fields for an owner (RF-116) — branch/restaurant name,
  receipt prefix, the shift-close toggle, and the tax setting. **Currency is locked to
  ILS**. Address / receipt-prefix are write-only (not readable to prefill).
- **Taxes** (RF-117): a per-branch owner setting, **default off**, no frozen rate
  (Q-001/Q-002); computed client-side and validated for total-consistency server-side —
  server-side tax-rate re-derivation in `submit_order` is a follow-up. Exclusive/added
  only (inclusive mode is stored but not wired).
- **Non-cash tenders** (RF-117): card/Bit/external are recorded as **external tenders**
  only — no payment processor, no real charge, no void/refund of a completed payment
  (D-023). Only cash affects the shift drawer.
- **Modifiers/sizes/variants** are not in the real POS menu yet (base-price
  items only), although the Menu tab can already manage them.
- **Shifts/cash drawer**: payments REQUIRE an open shift (RF-055); the POS
  auto-opens one (float 0) at staff sign-in. A shift can now be **closed and
  reconciled** from the POS ⋮ device menu → Close shift (RF-113) — counted cash
  in, server-computed expected/counted/difference out. Still deferred: a real
  **opening-float** entry, and the manager **reconcile** sign-off (`reconcile_shift`
  is server-only, not a client op).
- **On the web (Chrome)**, "secure storage" for the device-session token is
  browser-managed storage, not an OS keystore — fine for local development;
  a hardware pilot should run the POS/KDS as desktop/mobile builds.
- **PIN session window** is an interim 8h assumption (Q-009); device sessions
  have no expiry (revocation-bounded, Q-009).
- **Rate limiting** on device pairing/restore endpoints is deferred.
- **Realtime** is polling-first everywhere; no push.
- **Human RLS/security sign-off** is still required before real tenant data
  (AGENTS.md gate) — this build is a local pilot foundation, not a paid
  production deployment.

## 9. Full local validation (what CI runs + more)

```sh
dart format --set-exit-if-changed .
dart analyze apps packages
flutter test apps/dashboard && flutter test apps/pos && flutter test apps/kds && flutter test apps/admin
dart test packages/auth_identity
flutter test packages/feature_auth && flutter test packages/feature_admin
flutter test packages/feature_menu && flutter test packages/feature_kitchen
flutter test packages/design_system && flutter test packages/l10n
dart run tools/check_l10n.dart
bash tools/check_no_float_money.sh
bash tools/check_no_hardcoded_strings.sh
bash tools/check_secrets.sh
supabase db reset && supabase test db   # backend changes only
```

## 10. Browser smoke tests (RF-112)

A separate, **local-only** Playwright suite (`e2e/`) protects the visible MVP by
driving the real apps in a browser. RF-112A (the foundation) covers app
availability + basic real-mode UI safety (no demo banner in real mode,
Arabic/RTL first launch, KDS stays money-free). It **assumes the three apps are
already running in real mode** on their fixed ports (start them with the
`_run_*_real.bat` launchers above) and uses **only the public anon key** — never
a service-role key.

```sh
cd e2e
npm install                 # first time
npm run install:browsers    # first time — downloads Chromium
npm run smoke               # all specs (apps must be running)
npm run smoke:guards        # guard unit checks — no browser needed
```

The full onboarding → order → KDS-ticket journey is deferred to RF-112B/RF-112C.
See [e2e/README.md](../e2e/README.md).
