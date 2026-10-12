/// STOREFRONT-INTEGRATE-001 - the Storefront editor's DARK gate.
///
/// Owner decision 2026-10-12: the Storefront code is integrated into `main`
/// DARK. Until the bounded hosted pilot passes and a later, separately
/// approved change turns it on, a shipped Dashboard must be unable to publish
/// a real restaurant's storefront profile and unable to invoke the
/// `storefront-media-publish` Edge Function.
///
/// Compile-time FALSE unless a build passes
/// `--dart-define=RESTOFLOW_STOREFRONT_EDITOR=true`. The production web build
/// (`tools/vercel_build_web.sh`) passes only `RESTOFLOW_DEMO_MODE`,
/// `RESTOFLOW_SUPABASE_URL` and `RESTOFLOW_SUPABASE_ANON_KEY`, so every
/// production Dashboard builds NO Storefront seams: no profile read or write
/// (so no `is_published`), no media RPC and no function invocation - the
/// Settings card shows its existing honest "not connected" note. Inert, not
/// merely hidden (the `RESTOFLOW_PERF_DIAGNOSTICS` precedent of
/// DEVICE-RUNTIME-LARGE-TABLET-PERF-110).
const bool kStorefrontEditorEnabled = bool.fromEnvironment(
  'RESTOFLOW_STOREFRONT_EDITOR',
  defaultValue: false,
);
