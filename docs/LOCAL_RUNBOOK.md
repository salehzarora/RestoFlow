# RestoFlow — Local Runbook (Real MVP Flow)

> How to run the whole product locally, for real: local Supabase backend, owner
> dashboard, POS, and KDS. **Demo mode** (no backend, in-memory data, the
> default) and **Real Local mode** (local Supabase + real auth + real rows) are
> both first-class; the app always tells you which one you are in.
>
> This runbook is developer/pilot documentation. The authoritative architecture
> lives in `docs/` (see [ARCHITECTURE.md](ARCHITECTURE.md)); security rules in
> [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md). No secrets in
> this file — the local anon key is printed by the Supabase CLI on your machine.

---

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
- **Never use the `service_role` key in any app** (DECISION D-011). The apps
  reject service-role-looking keys at startup.

Useful:

```sh
supabase status          # re-print URLs + keys
supabase stop            # stop the stack (data preserved)
```

## 2. Open Supabase Studio

Studio runs at **http://127.0.0.1:54323** (see `supabase/config.toml`). Use it
to inspect tables (RLS still applies to app roles — Studio uses a privileged
local connection).

## 3. Reset the local database

Re-applies every migration to a clean local DB, then `seed.sql`:

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

All apps default to **Demo mode** (`RESTOFLOW_DEMO_MODE` defaults to `true`):
no backend, labelled demo data, safe to explore.

### Demo / preview launch (no backend needed)

```sh
# Dashboard (owner/manager)
cd apps/dashboard && flutter run -d chrome

# POS (cashier)
cd apps/pos && flutter run -d chrome

# KDS (kitchen)
cd apps/kds && flutter run -d chrome
```

### Real Local mode

Pass the three defines (URL + anon key from `supabase status`):

```sh
# Dashboard — real local
cd apps/dashboard
flutter run -d chrome \
  --dart-define=RESTOFLOW_DEMO_MODE=false \
  --dart-define=RESTOFLOW_SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=RESTOFLOW_SUPABASE_ANON_KEY=<anon key>

# POS — real local (same three defines)
cd apps/pos
flutter run -d chrome \
  --dart-define=RESTOFLOW_DEMO_MODE=false \
  --dart-define=RESTOFLOW_SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=RESTOFLOW_SUPABASE_ANON_KEY=<anon key>

# KDS — real local (same three defines)
cd apps/kds
flutter run -d chrome \
  --dart-define=RESTOFLOW_DEMO_MODE=false \
  --dart-define=RESTOFLOW_SUPABASE_URL=http://127.0.0.1:54321 \
  --dart-define=RESTOFLOW_SUPABASE_ANON_KEY=<anon key>
```

- Real mode with missing/invalid config never crashes and never falls back to
  fake data: the app shows a **"Real mode is not configured"** help page with
  these exact defines.
- POS/KDS device pairing uses **Supabase anonymous sign-in** (RF-161). In
  `supabase/config.toml`, local `auth` must allow anonymous sign-ins for
  device pairing to work; the hosted project needs the same toggle.

## 5. Create the first owner (dashboard)

1. Run the dashboard in real mode (above).
2. **Sign up** with email + password (local auth has email confirmation
   disabled, so sign-up signs you straight in).
3. The onboarding screen asks for **restaurant name** (+ optional branch
   name): submitting calls `public.create_organization`, which creates the
   organization → restaurant → branch → a default station → your `org_owner`
   membership.
4. You land in the real dashboard with your restaurant/branch shown in the
   context bar and a **Real** mode pill (demo shows **Demo**).

## 6. Create a device + pairing code (dashboard → Devices)

1. Dashboard → **Devices** tab.
2. **Create device** → label + type (**POS** or **KDS**).
3. On the new device card → **Issue code** → a one-time enrollment code is
   shown **once** (the backend stores only its hash). It expires (~15 min).
4. On the POS/KDS device (real mode), the pairing screen asks for this code.
   Redeeming it pairs the device and mints its device session (stored in
   OS-backed secure storage; restored on relaunch; type-checked per surface —
   a KDS session can never unlock a POS).
5. **Revoke** on a device card kills its pairing + sessions (the device falls
   back to the pairing screen).

## 7. Create staff + PINs (dashboard → Staff)

1. Dashboard → **Staff** tab.
2. **Add staff member** → display name + role (cashier / kitchen staff /
   manager). PIN-only operators get no login account (a synthetic identifier
   is created server-side; per-person identity is preserved — D-004).
3. On the staff card → **Set PIN** → enter a 4–8 digit PIN. The backend stores
   a **bcrypt hash** only (never the PIN). Wrong-PIN attempts are rate-limited
   with lockout.
4. On a paired POS/KDS, the PIN screen lists active staff for that branch:
   tap a name, enter the PIN, and a PIN session starts (8h window, Q-009
   interim).

## 8. Create printer configuration (dashboard → Printers)

1. Dashboard → **Printers** tab.
2. **Add printer** → display name, role (**receipt** / **kitchen**),
   connection type (**Network (Wi-Fi/LAN)**, **Bluetooth**, **USB**), paper
   width, and the connection details (host/port for network).
3. **Route** a printer to a station of the branch; enable/disable per printer.
4. Honesty: this saves **configuration** (backend-validated, RLS-scoped).
   Actual print dispatch from the apps is NOT wired in this build — the page
   says so. The ESC/POS print engine exists (`packages/printing`) with a
   network-first design; Bluetooth/USB transports are not installed yet
   (OPEN QUESTIONS Q-006/Q-015; hardware choices are human-gated). No fake
   "printed" success is ever shown.

## 9. Real order loop (POS → KDS → Dashboard)

1. POS (real, paired, PIN session as cashier): the menu comes from the real
   backend (`public.pos_menu` over the live `menu_items` rows). NOTE: the
   dashboard Menu tab is still demo for reads and there is **no seed file** —
   create menu categories/items via Supabase Studio (or the
   `public.menu_upsert_category` / `public.menu_upsert_item` RPCs as the
   signed-in owner) until the dashboard menu is wired for real reads.
2. Add items → submit: the order goes through the offline outbox →
   `public.sync_push` (`order.submit`) with an idempotency key
   (device + local operation id, D-022). Cash payment uses `payment.create`;
   the server assigns the receipt number. `record_payment` REQUIRES an open
   shift (RF-055): the POS opens one automatically (opening float 0) right
   after the staff PIN sign-in — closing/reconciling shifts and a real
   opening-float entry are still deferred with the RF-055 UI.
3. KDS (real, paired, PIN session as kitchen staff): the board polls
   `public.sync_pull` — financial entities (payments/shifts/cash drawer) are
   **never pulled** for kitchen staff, and the board renders no money (T-003).
   (Order rows do carry integer totals in the wire payload today — a
   pre-existing RF-057 shape; nothing money-typed is displayed or stored.)
   Advancing a ticket (accept → preparing → ready → bump/served) pushes
   `order.status` through the same sync pipeline and persists. **Recall** is
   demo-only (the backend is forward-only), so the live board hides it; if
   the session expires (~8h) the board offers **Sign in again**.
4. Dashboard → Overview shows the real sales summary (orders today, gross)
   with a manual **Refresh** (realtime is an enhancement, not a dependency).

## 10. Known limitations (honest list)

- **Printing hardware**: config only; no transport dispatch; no test print.
- **Dashboard Menu/Users/Settings tabs**: still demo-labelled (no real read
  RPCs yet); the POS menu read is real.
- **Modifiers/sizes/variants** are not in the real POS menu yet (base price
  items only).
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

## 11. Full local validation (what CI runs + more)

```sh
dart format --set-exit-if-changed .
dart analyze apps packages
flutter test apps/dashboard && flutter test apps/pos && flutter test apps/kds && flutter test apps/admin
dart test packages/auth_identity
flutter test packages/feature_auth && flutter test packages/feature_admin
flutter test packages/design_system && flutter test packages/l10n
dart run tools/check_l10n.dart
bash tools/check_no_float_money.sh
bash tools/check_no_hardcoded_strings.sh
bash tools/check_secrets.sh
supabase db reset && supabase test db   # backend changes only
```
