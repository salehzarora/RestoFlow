# BIZBOT-STOREFRONT-CINEMATIC-001 — final cinematic menu

Owner scope: the final mobile reference replaces food cards with independent product carousels. Preserve existing intro navigation, public catalog, cart/options/order/payment authority, dashboard content and isolated development. Preview publication is authorized; merge, hosted migration/configuration changes and Production publication require separate approval.

## Implementation

- Every category appears in source order, with a heading and independent carousel. Category buttons scroll smoothly to their section, retaining the other sections and their selections. Additional/empty categories use the same component.
- A large central product with smaller neighbours, transparent image surfaces, a subtle elliptical path and curved navigation arrows. Native horizontal touch gestures, RTL/LTR keyboard directions, circular navigation, one/two-item cases and reduced-motion handling stay in a presentation-only component.
- The existing delegated product opener receives the selected real product ID. Required options, cart calculations and order/payment code are unchanged. Existing search, kitchen picks and suggestion actions remain available; ordinary menu entry no longer repeats the editorial welcome hero.
- Warm dark surfaces, bold Arabic typography, accent highlights, owner-managed hero photograph extending beneath the navigation/footer, and a single restaurant information/contact panel. The hero highlight now preserves Arabic word order across highlighted spans.
- All colors use existing validated theme tokens. Primary/accent and optional text/button-text HEX fields remain configurable. The appearance extension now includes the allowlisted Rubik/Alexandria/system font selector, documented in `BIZBOT_STOREFRONT_CINEMATIC_001B.md`.
- No new dependency, RPC, CSP exception, payment behavior or authorization/RLS change. The appearance migration is still unapplied; font-aware readers must precede hosted migration/writer rollout.

## Complete interactive Preview

Dedicated `/s/sf-design-preview` route family, also under `/ar`, `/he` and `/en`. Intro, menu, search and cart reuse existing components with isolated fixture providers/cart namespace. Checkout/payment/review and arbitrary leaves return404. The authoritative live source switch and regular tenant routes are untouched.

Server access requires exactly `VERCEL_ENV=preview`, or an explicitly opted-in local fixture environment (`STOREFRONT_SOURCE=fixture SF_DESIGN_PREVIEW=1`, outside a provider). Routes are dynamic/noindex and return404 in Production. No order gateway origin is supplied; ordering remains disabled.

The public snapshot captured on2026-11-03 contains all20 real products, four categories, 11 option groups, actual prices, availability, contact, hours and service flags. Snapshot state is closed, pickup enabled, delivery disabled, ordering disabled. Presentation overrides only are selected in the Preview profile: `#151513`, `#f2ad79`, `#f7f2ea`, `#161410`, Alexandria, the approved welcome copy/format and prepared media. Current restaurant name/tagline remain as published in the snapshot. Hosted restaurant settings have not been changed.

## Images and evidence

Four drink originals already had transparency. Sixteen opaque images were processed into transparent preview derivatives using the built-in image generator; originals remain untouched. Their low-resolution sources caused reconstructed texture/logo details, so these are design-preview candidates rather than pixel-identical production photographs. Water/small cup labels and burger wrapper details especially warrant precise originals/manual matting before final asset approval; Mexican/Smash wrapper paper was removed to avoid wrong branding. See `BIZBOT_STOREFRONT_CINEMATIC_001_ASSETS.md`.

Preview media is optimized WebP, each below the existing256KB deployment cap. The hero is the previously prepared proposed background. Product imagery/configuration is confined to the preview dataset, never hardcoded in reusable UI components.

Real browser evidence at390×844:

- `01-mobile-welcome.png`
- `02-mobile-menu.png`
- `03-mobile-footer.png`
- `05-mobile-full-menu.png`
- `06-mobile-cups-drinks.png`
- `04-desktop-menu.png` at1440×1000.

## Focused verification

- Next production build and TypeScript passed.
- All448 Node tests passed, including carousel boundaries/direction, Preview environment guards, exact catalog preservation and font/color configuration.
- Real Chromium touch: independent selection, circular navigation, RTL horizontal swipe, natural vertical scrolling and no accidental product opening.
- All four categories/20products present, no mobile or desktop horizontal overflow; English and Hebrew layouts checked.
- Existing enabled local fixture: required options -> add -> cart count. No order submitted. No page errors or non-GET requests in the public-snapshot Preview smoke.
- Production-context HTTP check: preview menu returns404.
- GitHub preflight found no path overlap with open payment PRs#370/#371; main was still be57918. Work stays on the separate cinematic branch/worktree. Unpublished Claude changes remain unknown.
- At the first Preview delivery, Flutter/Dart and local PostgreSQL were unavailable. The followup executed the appearance SQL in disposable PostgreSQL/PGlite; full dashboard/pgTAP tests remain unrun. See the bounded evidence and limits in `BIZBOT_STOREFRONT_CINEMATIC_001_CLOSEOUT.md`. Historical browser suites pinning superseded design geometry were not run as a broad review cycle.

## Preview followup

`BIZBOT_STOREFRONT_CINEMATIC_001_CLOSEOUT.md` records the compact source-accurate
status copy, canonical-name investigation, actual appearance save/read/browser
roundtrip and complete-image desktop recapture. Order/payment/permission and
image-loading behavior are unchanged.

## Release boundary

Only the feature-branch Preview is requested for delivery. No merge, Production deployment, hosted migration or restaurant configuration mutation is authorized by this phase. The new snapshot routes are inaccessible in Production builds; their public food-image files are ordinary static assets, not private data.
