// RF-112 local browser smoke — content tokens for the real-mode safety checks.
//
// These lists are the DELIBERATELY-NARROW signals the smoke suite looks for in
// the app's accessible text. They are drawn from the actual l10n strings (see
// packages/l10n/lib/l10n/app_ar.arb + app_en.arb). Calibrate on the first live
// run (RF-112B) — the accessibility tree is the source of truth once the apps
// are actually running.

// Distinctive DEMO-mode banner / pill phrases. NOTE: we do NOT match the loose
// word "demo"/"تجريبي" because the honest real-mode config-help text legitimately
// says things like "or run in demo mode" / "شغّل الوضع التجريبي". Matching these
// full provenance phrases catches a demo build served on a real port WITHOUT
// false-failing on that help text. Arabic first (default locale), English too.
export const DEMO_BANNER_PHRASES: readonly string[] = [
  'بيانات تجريبية', // "Demo data" pill + menu/admin demo banner (ar)
  'بيانات منصة تجريبية', // admin "Demo platform data" notice (ar)
  'تغذية مطبخ تجريبية', // KDS "Demo kitchen feed" banner (ar)
  'طلب تجريبي', // POS "Demo order" notice (ar)
  'Demo data', // admin pill (en)
  'Demo platform data', // admin notice (en)
  'Demo kitchen feed', // KDS banner (en)
  'Demo order', // POS notice (en)
];

// The kitchen surface is money-REDACTED (SECURITY T-003): the KDS must never
// show prices/totals. Currency is ILS/₪ only, so ₪ is the strongest signal;
// "ILS"/"شيكل" back it up. Bare numbers are intentionally NOT flagged (order
// codes, ticket counts and times are legitimately numeric).
export const KDS_MONEY_TOKENS: readonly string[] = ['₪', 'ILS', 'شيكل'];

// A first-launch Arabic default is detectable as the presence of Arabic-script
// characters in the accessible text (RTL follows from the Arabic locale).
export const ARABIC_SCRIPT = /[؀-ۿ]/;
