# DEPLOYMENT — Hosted Supabase / Vercel Safety Runbook

> Scope: **RF-LIVE-001** (hosted Supabase/Vercel safety + deployment stabilization).
> This documents how the **public web app deploys** and the **hard safety rules** for
> connecting the clients to a **hosted** Supabase project. It does not authorize a
> production launch (see [PRODUCTION_READINESS.md](PRODUCTION_READINESS.md)); it
> makes it **safe to develop against hosted Supabase/Vercel** without leaking
> secrets or damaging live data. Local dev is owned by
> [LOCAL_RUNBOOK.md](LOCAL_RUNBOOK.md).

---

## 1. What deploys where

**One** Vercel project + **one** hosted Supabase project serve all three role apps
as Flutter web at their own paths (LIVE-APPS-001), so restaurant tablets open each
role separately:

| Path | Surface | Mode | Notes |
|---|---|---|---|
| `/` | `apps/dashboard` (owner/manager) | **REAL** | Manager tablet. GoTrue email/password sign-in. |
| `/pos`, `/pos/*` | `apps/pos` (cashier) | **REAL** | Cashier tablet. Anonymous device session → pairing → PIN (§8). |
| `/kds`, `/kds/*` | `apps/kds` (kitchen) | **REAL** | Kitchen tablet. Money-free; anonymous device session → pairing → PIN (§8). |
| — | `apps/admin` (platform admin) | — | **Out of scope / internal only** — no web target; separate plane (`platform_admin_guard` + aal2). If ever hosted it gets its **own** project/domain + security review (see §6). |

The Vercel build ([vercel.json](../vercel.json)) clones **Flutter pinned to `3.44.2`**
(matching CI) and runs [tools/vercel_build_web.sh](../tools/vercel_build_web.sh),
which builds **all three** apps `--release` — dashboard with `--base-href=/`, POS
with `--base-href=/pos/`, KDS with `--base-href=/kds/` — then copies the POS and
KDS builds **under** the dashboard output (`apps/dashboard/build/web/{pos,kds}`).
`outputDirectory` stays `apps/dashboard/build/web`. Ordered SPA rewrites give each
subtree its own fallback so hard-refresh / deep links resolve (real static assets
are served from the filesystem before rewrites apply):

```
/pos/(.*) → /pos/index.html      /kds/(.*) → /kds/index.html
/pos      → /pos/index.html      /kds      → /kds/index.html
/(.*)     → /index.html          (dashboard, catch-all LAST)
```

Each app uses `MaterialApp(home:)` (no top-level router) and `web/index.html`'s
`<base href="$FLUTTER_BASE_HREF">` placeholder, so subpath base-hrefs are native
and navigation stays base-href-relative.

---

## 2. Required environment variables (NAMES only — never commit values)

Set these as **Vercel Production/Preview environment variables** — the **same
values feed all three apps** (dashboard, POS, KDS). Values live in Vercel's env
store (or a secrets manager), **never in git**.

| Env var | Value class | Required | Notes |
|---|---|---|---|
| `RESTOFLOW_SUPABASE_URL` | public project URL | ✅ | A public endpoint, not a secret. |
| `RESTOFLOW_SUPABASE_ANON_KEY` | **anon / publishable key** | ✅ | **SAFE for clients** — RLS-gated, no elevated privilege. POS/KDS ride an **anonymous** device session over this key (§8), never a service-role key. |
| `RESTOFLOW_DEMO_MODE` | `false` | ✅ (pinned in the build script) | Pinned to `false` for all three apps by [tools/vercel_build_web.sh](../tools/vercel_build_web.sh) (invoked by vercel.json's `buildCommand`); enables the real auth gate — see §4. |
| `RESTOFLOW_AUTH_REDIRECT_URL` | public app URL | ⬜ optional | RF-LIVE-002 override for the sign-up email-confirmation redirect. Leave **unset** to derive it from the runtime web origin (correct for prod + preview); set only for a custom domain. Public URL, never a secret. See §5. |
| `RESTOFLOW_DASHBOARD_URL` | public Dashboard URL | ⬜ optional | RF-LIVE-002 — the hosted Dashboard URL the **Admin** app's "open the Dashboard" link points at. Unset falls back to the local dev URL. Public URL, never a secret. |
| `RESTOFLOW_PRINT_BRIDGE_URL` | — | ❌ **never on Vercel** | A per-device **LOCAL loopback** define (`http://127.0.0.1:8787`) for on-site ESC/POS printing; loopback-enforced client-side. It is a local-run concern only — **do not set it as a hosted Vercel env var** (a non-loopback value fails soft/dormant). |

These are the exact `--dart-define` names the apps read
([supabase_bootstrap_config.dart](../packages/auth_identity/lib/src/supabase_bootstrap_config.dart),
[auth_context_fetcher.dart](../packages/feature_auth/lib/src/auth_context_fetcher.dart)).
The generic `SUPABASE_URL` / `SUPABASE_ANON_KEY` names in
[.env.example](../.env.example) are a human template — **map them to the
`RESTOFLOW_`-prefixed names above** when configuring the deploy, or the app will
render the honest "real mode unconfigured" screen.

---

## 3. **SECURITY — no service-role key in any client (DECISION D-011)**

> A leaked **service-role** key bypasses PostgreSQL RLS entirely and breaks tenant
> isolation — **RISK R-003 (CRITICAL)**.

- **NEVER** put a `service_role` key, database password, or any `sb_secret_*` /
  `*service_role*` credential in a Vercel **frontend** env var, in `vercel.json`,
  in `.env.example`, or in any client build. Those are **server-side only**.
- The client is **defence-in-depth fail-closed**: `SupabaseBootstrapConfig`
  **rejects** a service-role / `sb_secret_`-shaped key and refuses to start real
  mode (it never echoes the offending value). Do not rely on this alone — never
  supply such a key in the first place.
- Both web clients initialise Supabase with `publishableKey:` (the anon key)
  **only**. All sensitive mutations go through `SECURITY DEFINER` RPCs; no client
  writes tables directly.
- If a service-role/secret key is ever exposed, treat it as **compromised**:
  rotate it immediately and purge from history — see
  [OPERATIONS_AND_RECOVERY.md](OPERATIONS_AND_RECOVERY.md).

---

## 4. Demo vs real mode — do not ship demo as production

- `RESTOFLOW_DEMO_MODE` **defaults to `true`** (demo, in-memory, no auth). A
  production build that **omits** the flag would serve the demo UI as if it were
  the product.
- The hosted web build **must** pass `--dart-define=RESTOFLOW_DEMO_MODE=false` for
  **all three apps** — [tools/vercel_build_web.sh](../tools/vercel_build_web.sh)
  (invoked by [vercel.json](../vercel.json)'s `buildCommand`) already does. **Never
  remove it**, and verify any alternate deploy path also sets it.
- If real mode is selected but the URL/anon key is missing or invalid, the app
  **fails closed** to an honest "unconfigured" help page — it never silently falls
  back to demo and never crashes.
- **RF-LIVE-002 demo-safety guard**: a **release** build left in demo mode **while
  valid real credentials are also present** (e.g. a hosted build that set the
  Supabase URL/anon key but forgot `RESTOFLOW_DEMO_MODE=false`) is an *accidental
  production demo*. The Dashboard and Admin apps now **fail closed** to an honest
  "demo mode is on with real credentials" page instead of serving demo data as if
  it were live. Explicit local/dev demo (no real config present) and debug builds
  are unaffected — so local demo still works exactly as before. **POS/KDS do not
  yet carry this guard** (LIVE-APPS-001 follow-up, §8) — for them the build pinning
  `RESTOFLOW_DEMO_MODE=false` is the safety, so never ship a POS/KDS build without it.

---

## 5. Auth redirect / Supabase project settings

The dashboard uses **email + password** sign-in and **email confirmation on
sign-up** only (admin adds **TOTP MFA**). There is **no** magic-link / OAuth /
password-reset deep-link callback surface.

- **Sign-up email confirmation** redirect is now **origin-derived in code**
  (RF-LIVE-002): `signUp` passes `emailRedirectTo` from the current web origin
  (`kIsWeb`-guarded, [auth_redirect.dart](../packages/feature_auth/lib/src/auth_redirect.dart)),
  so a confirmation link returns to whatever host is serving the app —
  `localhost:<port>` in dev, the Vercel domain in prod/preview — with no config.
  Set the optional `RESTOFLOW_AUTH_REDIRECT_URL` override only for a custom domain.
  Off the web (non-web builds) it returns null and the SDK/project default applies.
- Still set the Supabase project's **Redirect URLs** allowlist (Authentication →
  URL configuration) to include the Vercel production + preview domains (and any
  custom domain), so GoTrue accepts the origin-derived redirect target.

---

## 6. RF-LIVE-002 — hosted auth + mode-safety hardening (**done**)

The three RF-LIVE-001 follow-ups are now implemented (design/UI + config only; no
backend/RLS/RPC change):

- ✅ **Origin-derived email redirect** — `signUp` passes an origin-derived
  `emailRedirectTo` (shared, unit-tested `resolveAuthRedirectUrl` in feature_auth),
  with an optional `RESTOFLOW_AUTH_REDIRECT_URL` override for custom domains; null
  off-web. See §5.
- ✅ **Admin "open Dashboard" link** no longer hardcodes `localhost:57026` —
  `resolveDashboardUrl()` ([admin_platform_gate.dart](../apps/admin/lib/src/admin_platform_gate.dart))
  prefers `RESTOFLOW_DASHBOARD_URL` (hosted) and falls back to the local dev URL.
- ✅ **Production demo-mode safety** — a release build in demo mode with valid real
  credentials present fails closed to an honest help page (see §4), so demo can
  never ship as production; explicit local/dev demo is preserved.

---

## 7. Secret-file hygiene (local)

- Local secret env files (`*.env.local`, `supabasekey.env.local`, `.mcp.json`) are
  **git-ignored** ([.gitignore](../.gitignore)) and must **never** be committed —
  not even with `git add -f`.
- CI enforces this: `bash tools/check_secrets.sh` blocks un-ignored env/secret
  files and credential-shaped values (DECISION D-011).
- Only `*.example` templates (placeholder values) are tracked.

---

## 8. Hosted POS / KDS — device apps at `/pos` and `/kds` (LIVE-APPS-001)

POS (`/pos`) and KDS (`/kds`) are served from the **same** Vercel project +
Supabase project as the Dashboard (§1). They need **no app-code change** for
hosting; the security model is the same as an on-premise device.

- **Supabase prerequisite — Anonymous sign-ins MUST be enabled.** POS/KDS bootstrap
  an **anonymous device session** (`createAnonymousDeviceSession` / `…Transport`;
  an authenticated but **membership-less** principal — DECISION D-011, never a
  service-role key) to reach the pairing + PIN RPCs. Enable it in the Supabase
  dashboard → Authentication → Providers → **Anonymous**. If it is off, POS/KDS
  honestly render `DeviceSignInUnavailableView` (never a fake pairing).
- **Protected by pairing + PIN, NOT by a hidden URL.** A fresh tablet at `/pos` or
  `/kds` is **inert** until it is paired with a short-lived **enrollment code**
  issued from the Dashboard → Devices (RF-160), then unlocked per shift by a
  **staff PIN session** (`start_pin_session`, DECISION D-006). The anonymous
  session carries **no membership**, so RLS returns **zero tenant data**; it can
  only attempt pairing, and pairing is **rate-limited** (RF-118 brute-force
  lockout). So a public URL is safe — the URL is not the secret.
- **Pairing PERSISTS across refresh / browser restart (LIVE-DEVICE-001).** A paired
  tablet must stay paired until explicitly unpaired or revoked — pressing F5 must
  NOT return to the pairing screen. The paired-device credential (`{deviceId,
  sessionToken}`) is persisted on the device and re-proven on every launch via the
  **token-proven** `restore_device_session` (no principal binding, so a fresh
  anonymous session each launch is fine). **Web:** persisted in `localStorage` via
  `shared_preferences` (the same durable store the RF-114 outbox uses) — chosen
  because `flutter_secure_storage`'s web backing did not reliably survive refresh
  in the hosted build, and on web it is anyway just AES-in-`localStorage` with a
  same-origin key (no OS keychain), so this is no less protected. **Native:** the
  OS Keychain/Keystore via `flutter_secure_storage` (unchanged). The token is never
  logged or shown. Because `/pos` and `/kds` share **one origin** (and
  `localStorage` is per-origin, not per-path), POS and KDS use **surface-specific
  storage keys** (`restoflow.pos.device_session.v1` vs
  `restoflow.kds.device_session.v1`), so one surface never reads or clears the
  other's credential.
- **Staff PIN session is SEPARATE from device pairing.** The device stays paired;
  the per-shift staff **PIN session** may expire (RF-118) — an expired PIN shows
  the **PIN sign-in**, NOT the pairing screen. On launch: paired device restored →
  PIN sign-in (enter PIN) → surface.
- **Recovery / reset:** the ⋮ device-settings sheet has an explicit **Unpair**
  action (`DeviceSessionManager.unpair` — best-effort server `revoke_device_session`
  + local clear), returning the tablet to the pairing screen. A credential the
  server has revoked (or a corrupt/wrong-type one) is cleared automatically on the
  next restore and falls back to pairing — self-recovering, never a fake session.
- **Easier pairing (LIVE-DEVICE-001):** the pairing screen **prefills** the code
  from a `…/pos?pair=CODE` / `…/kds?pair=CODE` URL (a Dashboard-generated link, or
  a QR that encodes it), so staff don't type it by hand. It is prefill-only — the
  operator still taps **Pair**; the code is never auto-redeemed. The code is
  short-lived, single-use, and rate-limited, so it is not a durable secret. *(A
  Dashboard QR that renders this link is a natural follow-up — the `qr` package is
  already a dependency.)*
- **Revocation:** a lost/stolen tablet is revoked from the Dashboard (RF-160/RF-161),
  removing future access including across the offline window (RISK R-007).
- **No service-role key** ever reaches POS/KDS (or any client) — anon/publishable
  only (§3). **KDS is money-free** (SECURITY T-003): it reads tickets via
  `sync_pull` and shows no prices.
- **`RESTOFLOW_PRINT_BRIDGE_URL` is NOT a hosted var** — it is a per-device local
  loopback define for on-site ESC/POS printing (§2); never set it on Vercel.
- **Follow-up (deferred):** extend the RF-LIVE-002 production **demo-mode
  misconfiguration guard** (§4) to POS/KDS so a release build with real credentials
  but a missing `RESTOFLOW_DEMO_MODE=false` fails closed there too. Until then the
  build pinning the flag is the safety.
- **Admin stays out** of this deployment — internal platform plane only (§1/§6).

## 9. Hosted Dashboard — context restore + reports fallback (LIVE-DASHBOARD-001)

Two hosted-only Dashboard behaviours were hardened; **both are client-side — no
live DB migration, no schema/RLS/RPC change.**

- **Refresh no longer flashes "Set up your restaurant."** On a hosted F5 the
  restored Supabase session's JWT can attach to the transport **after** the first
  `get_my_context` fires, so that first call runs effectively anonymous and the
  `SECURITY DEFINER` resolver returns **42501** (AuthDenied) even for a
  fully-provisioned owner — which previously routed straight to onboarding /
  create-restaurant. The auth flow now **retries the context load a bounded number
  of times** (`DashboardAuthFlow.contextRetryBackoff`, default 350 ms × up to 3
  attempts) before rendering any terminal state, so that race **self-heals to the
  dashboard**. While loading it shows the skeleton; a stable network/server error
  shows **retry/error**; onboarding is reached only on a **confirmed** no-context —
  either `NoMemberships` (a successful `get_my_context` that clearly enumerated
  zero memberships) or a **stable** 42501 that survived the retries (a genuinely new
  principal whose `app_user` is not bootstrapped until `create_organization`, which
  is **idempotent** — so even a mis-routed existing owner is never duplicated). A
  42501 is **never** silently turned into a new org/restaurant.
- **Overview no longer shows "Couldn't load reports."** The RF-REPORT-001
  `owner_daily_report` migration is merged but **intentionally not applied to live**
  until R-003 sign-off, so on production that function does not exist and PostgREST
  answers with a **"could not find the function"** error (`PGRST202` / `404`). The
  real owner-reports repository now treats **only that missing-RPC signature** as a
  cue to fall back to the already-deployed **`public.sales_summary`**, mapping the
  limited figures it provides (orders + completed-payment gross; everything else
  honest zero/empty). It stays the RF-140 **"live · limited"** report. The fallback
  is **fail-closed**: it **never** fires on a permission / tenant-isolation / auth
  denial (**42501**) or on any non-missing server error, and a rejected
  `sales_summary` (e.g. a below-manager caller) still throws — a denied caller
  **never** silently sees fallback data. **When `owner_daily_report` is applied to
  live (post R-003), the fallback simply stops triggering** — no client change is
  needed to retire it.

## 10. Hosted Dashboard — live reporting clarity + devices cleanup (LIVE-UX-001)

Follow-ups to §9, making the hosted Dashboard read as **intentional** rather than
broken/old. **All client-side — no live DB migration, no schema/RLS/RPC change, no
fabricated data.**

**Live reporting clarity (Overview).** On production the Overview renders the
`sales_summary` fallback (§9), which lacks the richer analytics — so it previously
looked bare next to the demo. Now:

- **A safe "vs yesterday" comparison is derived** from `sales_summary.last_7_days`
  (`[len-2]` = yesterday): `orderCount` from yesterday's `orders_count`, and
  gross/net/cash all from yesterday's completed-payment `gross_minor` (the SAME
  identity the today-block uses in this limited build — net/cash mirror gross). This
  lights up the KPI deltas **honestly**; a short/zero/malformed prior yields **no**
  delta (`deltaPercent` guards it). It is deliberately **not** used to synthesize a
  completed/unpaid comparison (`last_7_days` has no per-day `payments_count`).
- **Empty section cards are hidden** (sales-by-branch, top items, recent orders) and
  a calm **"more analytics coming"** note explains the gap, under a **titled** live
  banner — so the limited state looks deliberate. **Nothing is fabricated.**
- **The sales-by-hour chart stays hidden** in live mode — `sales_summary` has no
  hourly granularity, so no curve is synthesised. The **live chart + top items +
  per-branch + recent orders require the full `public.owner_daily_report`
  (RF-REPORT-002 slices) deployed to live after R-003 sign-off**; until then the
  "more analytics coming" note is the honest placeholder, and it retires itself once
  the richer report lands.

**Devices cleanup (Devices tab).** A revoked device is terminal
(`devices.is_active=false`): it cannot pair and cannot re-issue an enrollment code
(`issue_device_enrollment_code` requires `is_active`, so it fails closed with
**42501** — which the client can only render as a misleading *"you don't have
permission"* toast). So:

- **Revoked devices are removed from the active list** and collapsed under a
  read-only **"Revoked devices (N)"** section (expanding it is the "show revoked"
  toggle). A small **count line** shows live vs revoked totals.
- **Revoked devices offer neither Revoke nor Issue code** — the misleading toast can
  no longer fire from a visible-but-impossible action. (`none`/`code_expired`/
  `rejected` devices are still active, so re-issuing a fresh code stays available.)
- **A below-manager role never sees the manage actions** (create/revoke/issue) — they
  are hidden *before* the click (`canManage` = rank ≥ manager, matching every device
  RPC's gate), so a lack-of-authority denial is never surfaced as a late toast.
- **Setup-checklist device counts exclude revoked** devices, so a branch whose only
  POS/KDS was revoked is correctly prompted to create a new one (a revoked device no
  longer silently satisfies the step or inflates the device total).

> Diagnosis note: the *"you don't have permission"* toast was **not** a real
> permission problem and **not** a role-rank mismatch (list/create/issue/revoke all
> gate at rank ≥ manager). It was a UI action-visibility bug — offering "Issue code"
> on an inactive (revoked) device — plus a lossy client error map (42501 → permission
> denied). The SQL authority model is internally consistent and unchanged.

## 11. QR pairing + real sales-by-hour reporting (LIVE-OPS-001 / RF-REPORT-002)

**QR pairing (Dashboard Devices).** Issuing a POS/KDS enrollment code now shows a
pairing panel with a **locally-rendered QR** + a copyable hosted link + the manual
code, so staff can point a tablet straight at the pairing screen (which already
prefills `?pair=CODE`, LIVE-DEVICE-001). **All client-side.**

- The link is **origin-derived** (`{scheme}://{host}[:port]/pos?pair=CODE` or
  `/kds`), built from the current web origin — it works on localhost, Vercel
  preview/production, and any future custom domain. **Nothing is hardcoded** (no
  `resto-flow-phi.vercel.app`). The Dashboard's own path/query never leaks in.
- The **QR is OFFLINE** — `qr_flutter` (pure-Dart `qr` encoder + `CustomPaint`).
  **No external QR API, no network.** The dependency is scoped to the **Dashboard**
  app; `feature_admin` stays QR-free via an injected panel seam.
- **Display only** — the Dashboard never auto-pairs; the operator still taps **Pair**
  on the tablet. The code is short-lived, single-use, rate-limited server-side, and
  **never logged**. A device type with no app route (not pos/kds) shows the **manual
  code only** (no link/QR). Revoked devices still offer no Issue-code (LIVE-UX-001),
  and the below-manager visibility rules are unchanged.

**Real sales-by-hour (RF-REPORT-002).** The Overview's DESIGN-002 sales-by-hour
chart can now render **real** data — a top-level `hourly` array of 24 branch-local
buckets (today's **billed** net per hour) added to `owner_daily_report`
(API_CONTRACT §4.19a). **Backend migration is NOT applied to the hosted DB.**

- **The live chart stays unavailable in production until the RF-REPORT-002 migration
  (`20260706090000`, a forward-only `CREATE OR REPLACE`) is applied to the hosted
  Supabase after R-003 human RLS/security sign-off** (shared gate with
  `sales_summary`/RF-REPORT-001). Locally it is validated by pgTAP only.
- Until then the Dashboard uses the `sales_summary` fallback (LIVE-DASHBOARD-001),
  which has **no hourly source** — the client leaves `hourlyNetSales` empty and the
  chart **stays hidden**. The fallback **never fabricates** hourly data.
- When applied, the chart renders only when there is **real** hourly data (a day
  with no billed net sales maps to empty → the chart hides, never a flat-zero
  placeholder). Money stays integer minor (D-007); KDS is untouched (money-free).
