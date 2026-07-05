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
| `RESTOFLOW_AUTH_REDIRECT_URL` | public app URL | ⬜ optional | RF-LIVE-002 override for the sign-up email-confirmation redirect. Leave **unset** to derive it from the runtime web origin (correct for prod + preview); set only for a custom domain. Public URL, never a secret. See §5. |
| `RESTOFLOW_DASHBOARD_URL` | public Dashboard URL | ⬜ optional | RF-LIVE-002 — the hosted Dashboard URL the **Admin** app's "open the Dashboard" link points at. Unset falls back to the local dev URL. Public URL, never a secret. |

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
- **RF-LIVE-002 demo-safety guard**: a **release** build left in demo mode **while
  valid real credentials are also present** (e.g. a hosted build that set the
  Supabase URL/anon key but forgot `RESTOFLOW_DEMO_MODE=false`) is an *accidental
  production demo*. The Dashboard and Admin apps now **fail closed** to an honest
  "demo mode is on with real credentials" page instead of serving demo data as if
  it were live. Explicit local/dev demo (no real config present) and debug builds
  are unaffected — so local demo still works exactly as before.

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
