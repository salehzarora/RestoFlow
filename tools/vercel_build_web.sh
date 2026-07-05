#!/usr/bin/env bash
# ============================================================================
# RestoFlow — Vercel build step for the PUBLIC web apps (LIVE-APPS-001).
#
# Builds ALL THREE role apps as Flutter web and assembles them into ONE static
# output directory so real restaurant tablets open each role at its own path on
# one hosted Vercel project + one hosted Supabase project:
#     /       -> Dashboard (manager)   apps/dashboard
#     /pos    -> POS (cashier)         apps/pos
#     /kds    -> KDS (kitchen)         apps/kds
# Admin is intentionally NOT built here (internal platform plane, no web target).
#
# HOW: each app is built with its own Flutter --base-href (the web/index.html
# `<base href="$FLUTTER_BASE_HREF">` placeholder is substituted at build time),
# then POS/KDS are copied UNDER the dashboard output (apps/dashboard/build/web/
# {pos,kds}); vercel.json `outputDirectory` stays apps/dashboard/build/web and
# its ordered rewrites give each subtree its own SPA fallback. base-href must
# start AND end with '/'.
#
# SECURITY (DECISION D-011): every app is built in REAL mode
# (--dart-define=RESTOFLOW_DEMO_MODE=false) with ONLY the PUBLIC anon key +
# project URL, passed ONLY by env-var NAME ($RESTOFLOW_SUPABASE_URL /
# $RESTOFLOW_SUPABASE_ANON_KEY, set in the Vercel project env) — NEVER a
# service-role/secret key and NEVER a literal secret in source. POS/KDS reach the
# backend via an anonymous device session (pairing + PIN); the anon key is public
# by design. RESTOFLOW_PRINT_BRIDGE_URL is a per-device LOCAL loopback define,
# NOT a hosted var — it is never set here.
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

# 4. Assemble: place POS + KDS UNDER the dashboard output. Each app's assets and
#    service worker are self-contained under its own base-href, so there is no
#    collision with the dashboard at the root. Remove any stale copies first so a
#    rebuild is deterministic.
rm -rf apps/dashboard/build/web/pos apps/dashboard/build/web/kds
cp -r apps/pos/build/web apps/dashboard/build/web/pos
cp -r apps/kds/build/web apps/dashboard/build/web/kds

echo "web build assembled: / (dashboard), /pos (POS), /kds (KDS)"
