#!/usr/bin/env bash
# ============================================================================
# RestoFlow — Vercel build step for the PUBLIC dashboard web app.
#
# Extracted verbatim from vercel.json's `buildCommand` so that field stays a
# short `bash tools/vercel_build_dashboard.sh`, well under Vercel's 256-char
# `buildCommand` schema maxLength (the inline command was ~238 chars and grows
# each time a new --dart-define is added, which tripped vercel.json schema
# validation on deploy). Behavior is IDENTICAL to the previous inline command.
#
# SECURITY (DECISION D-011): passes ONLY the PUBLIC anon key + project URL, and
# ONLY by env-var NAME ($RESTOFLOW_SUPABASE_URL / $RESTOFLOW_SUPABASE_ANON_KEY,
# set in the Vercel project environment) — NEVER a service-role/secret key and
# NEVER a literal secret in source. RESTOFLOW_DEMO_MODE is pinned to `false` so
# the hosted deploy runs in REAL mode (not demo). Output stays
# apps/dashboard/build/web (see vercel.json `outputDirectory`).
#
# Run from the repo root (Vercel runs the build command there); Flutter is the
# pinned clone from vercel.json `installCommand` at ../../flutter.
# ============================================================================
set -eo pipefail

cd apps/dashboard
../../flutter/bin/flutter build web --release \
  --dart-define=RESTOFLOW_DEMO_MODE=false \
  --dart-define=RESTOFLOW_SUPABASE_URL="$RESTOFLOW_SUPABASE_URL" \
  --dart-define=RESTOFLOW_SUPABASE_ANON_KEY="$RESTOFLOW_SUPABASE_ANON_KEY"
