#!/usr/bin/env bash
# ============================================================================
# RestoFlow — Vercel build step for the PUBLIC web apps (LIVE-APPS-001 +
# KIOSK-001-WEB-087).
#
# Builds ALL FOUR public apps as Flutter web and assembles them into ONE static
# output directory so real restaurant devices open each role at its own path on
# one hosted Vercel project + one hosted Supabase project:
#     /       -> Dashboard (manager)                 apps/dashboard
#     /pos    -> POS (cashier)                       apps/pos
#     /kds    -> KDS (kitchen)                       apps/kds
#     /kiosk  -> Customer self-service kiosk         apps/kiosk
# Admin is intentionally NOT built here (internal platform plane, no web target).
#
# HOW: each app is built with its own Flutter --base-href (the web/index.html
# `<base href="$FLUTTER_BASE_HREF">` placeholder is substituted at build time),
# then POS/KDS/Kiosk are copied UNDER the dashboard output (apps/dashboard/
# build/web/{pos,kds,kiosk}); vercel.json `outputDirectory` stays
# apps/dashboard/build/web and its ordered rewrites give each subtree its own
# SPA fallback. base-href must start AND end with '/'.
#
# SECURITY (DECISION D-011): every app is built in REAL mode
# (--dart-define=RESTOFLOW_DEMO_MODE=false) with ONLY the PUBLIC anon key +
# project URL, passed ONLY by env-var NAME ($RESTOFLOW_SUPABASE_URL /
# $RESTOFLOW_SUPABASE_ANON_KEY, set in the Vercel project env) — NEVER a
# service-role/secret key and NEVER a literal secret in source. POS/KDS/Kiosk
# reach the backend via an anonymous device session (pairing; PIN for staff
# surfaces); the anon key is public by design. The kiosk is a READ-side device
# surface here: real order submission stays gated OFF in app logic
# (kioskOrderingEnabledProvider FALSE in real composition) until its own
# server-approved phase. RESTOFLOW_PRINT_BRIDGE_URL is a per-device LOCAL
# loopback define, NOT a hosted var — it is never set here.
#
# Run from the repo root (Vercel runs the build command there); Flutter is the
# pinned clone from vercel.json `installCommand` at ../../flutter.
# ============================================================================
set -eo pipefail

FLUTTER="$(pwd)/flutter/bin/flutter"
DEFINES=(
  --dart-define=RESTOFLOW_DEMO_MODE=false
  --dart-define=RESTOFLOW_SUPABASE_URL="$RESTOFLOW_SUPABASE_URL"
  --dart-define=RESTOFLOW_SUPABASE_ANON_KEY="$RESTOFLOW_SUPABASE_ANON_KEY"
)

# 1. Dashboard (root, base-href /) — the output directory Vercel serves.
(cd apps/dashboard && "$FLUTTER" build web --release --base-href=/ "${DEFINES[@]}")

# 2. POS (base-href /pos/).
(cd apps/pos && "$FLUTTER" build web --release --base-href=/pos/ "${DEFINES[@]}")

# 3. KDS (base-href /kds/).
(cd apps/kds && "$FLUTTER" build web --release --base-href=/kds/ "${DEFINES[@]}")

# 4. Kiosk (base-href /kiosk/) — same public defines, no kiosk-only secrets.
(cd apps/kiosk && "$FLUTTER" build web --release --base-href=/kiosk/ "${DEFINES[@]}")

# 5. Assemble: place POS + KDS + Kiosk UNDER the dashboard output. Each app's
#    assets and service worker are self-contained under its own base-href, so
#    there is no collision with the dashboard at the root. Remove any stale
#    copies first so a rebuild is deterministic.
rm -rf apps/dashboard/build/web/pos apps/dashboard/build/web/kds apps/dashboard/build/web/kiosk
cp -r apps/pos/build/web apps/dashboard/build/web/pos
cp -r apps/kds/build/web apps/dashboard/build/web/kds
cp -r apps/kiosk/build/web apps/dashboard/build/web/kiosk

echo "web build assembled: / (dashboard), /pos (POS), /kds (KDS), /kiosk (Kiosk)"
