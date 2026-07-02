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
   automatically (opening float 0) right after the staff PIN sign-in —
   closing/reconciling shifts and a real opening-float entry are still
   deferred with the RF-055 UI.
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

## 8. Known limitations (honest list)

- **Printing hardware**: config only; no transport dispatch; no test print.
  The ESC/POS engine exists (`packages/printing`, network-first design);
  Bluetooth/USB transports are not installed (Q-006/Q-015, human-gated).
- **Users tab**: no member read API yet — honest empty state, no real member
  management from the dashboard.
- **Settings tab**: read-only real values; no settings read/save round-trip.
- **Modifiers/sizes/variants** are not in the real POS menu yet (base-price
  items only), although the Menu tab can already manage them.
- **Shifts/cash drawer**: payments REQUIRE an open shift (RF-055); the POS
  auto-opens one (float 0) at staff sign-in, but there is no UI to close or
  reconcile a shift yet, and no real opening-float entry.
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
