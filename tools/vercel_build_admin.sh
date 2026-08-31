#!/usr/bin/env bash
# ============================================================================
# RestoFlow — Vercel build step for the INTERNAL PLATFORM CONSOLE (ADMIN-126B).
#
# This builds `apps/admin` ALONE, for its OWN Vercel project. It is deliberately
# NOT part of `tools/vercel_build_web.sh`: the public project serves the four
# tenant-facing apps (/, /pos, /kds, /kiosk) and the platform console must not
# share an origin with them. Putting it at /admin on the public project would
# hand every restaurant device the console's bundle and give the two surfaces
# one browser storage scope — `admin_web_target_125a_test.dart` fails if it ever
# drifts into the public build, and that guard should stay true.
#
# SECURITY (DECISION D-011): built in REAL mode with ONLY the PUBLIC anon key +
# project URL, passed by env-var NAME from the Vercel project settings — NEVER a
# service-role/secret key, and never a literal secret in source. Console access
# is not granted by this bundle: entry requires an active `platform_admin_grants`
# row plus a verified `aal2` (MFA) session plus a typed reason, all enforced
# server-side by `app.platform_admin_guard` (D-026).
#
# RESTOFLOW_DASHBOARD_URL is the PUBLIC origin of the tenant Dashboard. The
# console needs it for two things: the "this is the platform panel" explainer
# shown to a non-admin, and the ADMIN-126B support handoff, which opens
#   <RESTOFLOW_DASHBOARD_URL>/#support=<one-time token>
# in a new tab. The token lives in the FRAGMENT, so it is never sent to a server
# and never reaches an access log. It is single-use and expires in ~60 seconds.
#
# Vercel project settings for this project:
#   Root directory ........ apps/admin   (NOT blank — see below)
#   Install / Build / Output / Rewrites ... come from apps/admin/vercel.json
#   Environment ........... RESTOFLOW_SUPABASE_URL
#                           RESTOFLOW_SUPABASE_ANON_KEY   (publishable/anon ONLY)
#                           RESTOFLOW_DASHBOARD_URL
#   Deployment protection . ON (this is an internal plane, not a public site)
#
# WHY Root directory = apps/admin (ADMIN-126B2 fix). A Vercel project reads a
# vercel.json ONLY from its Root Directory. With a BLANK root it would read the
# REPO-ROOT vercel.json — the PUBLIC tenant project's config — which builds the
# dashboard bundle and never runs this script, and apps/admin/vercel.json (incl.
# its SPA rewrite) would be dead. Pointing the root at apps/admin makes
# apps/admin/vercel.json authoritative: its install/build commands `cd ../..`
# back to the repo root (Vercel still checks out the whole monorepo) so this
# script and the pinned Flutter clone resolve exactly as before, and
# outputDirectory `build/web` is apps/admin/build/web. The public project's
# repo-root vercel.json + tools/vercel_build_web.sh are untouched, so
# admin_web_target_125a_test.dart still proves the console never enters the
# public build.
# ============================================================================
set -eo pipefail

FLUTTER="$(pwd)/flutter/bin/flutter"

if [ -z "$RESTOFLOW_DASHBOARD_URL" ]; then
  # Fail loudly rather than shipping a console whose support handoff opens a
  # localhost URL nobody can reach.
  echo "RESTOFLOW_DASHBOARD_URL is not set — the support handoff would point at the local fallback." >&2
  exit 1
fi

(cd apps/admin && "$FLUTTER" build web --release --base-href=/ \
  --dart-define=RESTOFLOW_DEMO_MODE=false \
  --dart-define=RESTOFLOW_SUPABASE_URL="$RESTOFLOW_SUPABASE_URL" \
  --dart-define=RESTOFLOW_SUPABASE_ANON_KEY="$RESTOFLOW_SUPABASE_ANON_KEY" \
  --dart-define=RESTOFLOW_DASHBOARD_URL="$RESTOFLOW_DASHBOARD_URL")

echo "platform console built: apps/admin/build/web (dashboard handoff -> $RESTOFLOW_DASHBOARD_URL)"
