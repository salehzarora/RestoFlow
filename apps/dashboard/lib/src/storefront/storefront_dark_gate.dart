/// STOREFRONT-INTEGRATE-001 - the Storefront editor's build gate.
///
/// Owner decision 2026-10-12: the Storefront code was integrated into `main`
/// DARK. A Dashboard build without the gate must be unable to publish a real
/// restaurant's storefront profile and unable to invoke the
/// `storefront-media-publish` Edge Function.
///
/// Compile-time FALSE unless a build passes
/// `--dart-define=RESTOFLOW_STOREFRONT_EDITOR=true`. STOREFRONT-PRODUCTION-
/// ENABLE-001: the production web build (`tools/vercel_build_web.sh`) passes
/// the define to the Dashboard ONLY, and `true` ONLY when the Vercel env var
/// of the same name is exactly `true` - an owner setting for the Production
/// environment only; Preview and Development builds stay closed. While the
/// gate is closed the shell builds NO Storefront seams: no profile read or
/// write (so no `is_published`), no media RPC, no function invocation, and
/// Settings shows no Storefront card. Even with the gate open, platform
/// support mode gets no seams (dashboard_shell.dart). Inert, not merely
/// hidden (the `RESTOFLOW_PERF_DIAGNOSTICS` precedent of
/// DEVICE-RUNTIME-LARGE-TABLET-PERF-110).
const bool kStorefrontEditorEnabled = bool.fromEnvironment(
  'RESTOFLOW_STOREFRONT_EDITOR',
  defaultValue: false,
);
