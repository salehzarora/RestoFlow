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

| Surface | Target | Mode | Notes |
|---|---|---|---|
| `apps/dashboard` (owner/manager web) | **Vercel** (public web) | **REAL** | The only surface wired for hosted web deploy today ([vercel.json](../vercel.json)). |
| `apps/admin` (platform admin) | not hosted yet | — | Server-gated by `platform_admin_guard` + aal2; treat as local/internal until a hosted target is defined (see §6). |
| `apps/pos`, `apps/kds` | device apps | REAL | Paired-device auth; not web-deployed. |

The Vercel build ([vercel.json](../vercel.json)) clones **Flutter pinned to `3.44.2`**
(matching CI), builds `apps/dashboard` web `--release`, outputs
`apps/dashboard/build/web`, and adds an SPA rewrite (`/(.*) → /index.html`) so
GoRouter deep links resolve on hard refresh.

---

## 2. Required environment variables (NAMES only — never commit values)

Set these as **Vercel Production/Preview environment variables**. Values live in
Vercel's env store (or a secrets manager), **never in git**.

| Env var | Value class | Required | Notes |
|---|---|---|---|
| `RESTOFLOW_SUPABASE_URL` | public project URL | ✅ | A public endpoint, not a secret. |
| `RESTOFLOW_SUPABASE_ANON_KEY` | **anon / publishable key** | ✅ | **SAFE for clients** — RLS-gated, no elevated privilege. |
| `RESTOFLOW_DEMO_MODE` | `false` | ✅ (set in vercel.json) | Enables the real auth gate; see §4. |

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
- The hosted dashboard build **must** pass `--dart-define=RESTOFLOW_DEMO_MODE=false`
  — [vercel.json](../vercel.json) already does. **Never remove it**, and verify any
  alternate deploy path also sets it.
- If real mode is selected but the URL/anon key is missing or invalid, the app
  **fails closed** to an honest "unconfigured" help page — it never silently falls
  back to demo and never crashes.

---

## 5. Auth redirect / Supabase project settings

The dashboard uses **email + password** sign-in and **email confirmation on
sign-up** only (admin adds **TOTP MFA**). There is **no** magic-link / OAuth /
password-reset deep-link callback surface.

- **Sign-up email confirmation** redirect is governed by the **Supabase project's
  Site URL / Redirect URLs** (the app does not yet pass `emailRedirectTo`). For the
  hosted dashboard you **must** set, in the Supabase dashboard → Authentication →
  URL configuration:
  - **Site URL** → the Vercel production domain.
  - **Redirect URLs** allowlist → the Vercel production + preview domains.
- Do **not** leave these at a `localhost`/dev value, or confirmed owners will be
  redirected to the wrong host. *(Deriving the redirect from the runtime origin in
  code is a tracked follow-up — see §6.)*

---

## 6. Known limitations / follow-ups (proposed **RF-LIVE-002**)

These are **not** fixed here (they change shipped app behaviour and are beyond
RF-LIVE-001's minimal-safety scope); track them next:

- **Origin-derived email redirect**: pass `emailRedirectTo` from the runtime web
  origin (`kIsWeb`-guarded) on `signUp`, plus a test, so confirmation links follow
  the deploy host automatically instead of relying on Supabase Site URL config.
- **Admin "open Dashboard" link** hardcodes `http://localhost:57026`
  ([admin_platform_gate.dart](../apps/admin/lib/src/admin_platform_gate.dart)) —
  derive it from config/origin before hosting the Admin app.
- **Demo-mode defence-in-depth**: assert a release build is not in demo mode (or
  invert the default so real must be opted into), so demo can never ship as prod.

---

## 7. Secret-file hygiene (local)

- Local secret env files (`*.env.local`, `supabasekey.env.local`, `.mcp.json`) are
  **git-ignored** ([.gitignore](../.gitignore)) and must **never** be committed —
  not even with `git add -f`.
- CI enforces this: `bash tools/check_secrets.sh` blocks un-ignored env/secret
  files and credential-shaped values (DECISION D-011).
- Only `*.example` templates (placeholder values) are tracked.
