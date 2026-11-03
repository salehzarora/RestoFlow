# BIZBOT-STOREFRONT-CINEMATIC-001 — independent menu background

V5, 2026-11-03. Continue the isolated cinematic Preview branch. The menu now
uses the supplied warm charcoal texture independently of the welcome Hero.
The previous canonical-name and source-accurate status-copy decisions remain
unchanged, as do catalog, options, cart, order admission and payment behavior.

## Presentation and dashboard contract

One decorative image layer spans the complete menu document through its footer.
It does not restart for each section or end at viewport height. The abstract
texture fills the mobile canvas and uses cover on desktop; product imagery and
controls remain separate. Existing footer identity and welcome Hero are retained.
The overlay uses the configured background color and the existing `ThemeScope`
CSSOM path, without inline-style/CSP changes. No custom image means the existing
Hero-derived menu treatment is rendered instead.

| Private appearance field | Public field | Behavior |
| --- | --- | --- |
| `menu_background_media_id` | `menu_background_url` | Optional eligible published media UUID; null clears the separate image. Only the URL is public. |
| `menu_background_dim` | `menu_background_dim` | Optional integer 0–80; null/absence uses 15% with a selected image. |

The two existing color keys remain required when `appearance` exists; font and
background keys remain optional. Older writers preserve absent optional fields;
explicit null clears them. The same content save/version/replay and media
publisher/selector are reused. Eligibility is checked against the existing
restaurant/branch media scope. Usage listing/retract protection and same-source
republication include the new reference, without changing the Hero pointer.
See [001B](BIZBOT_STOREFRONT_CINEMATIC_001B.md) for the complete appearance contract.

## Supplied texture

Original: `Warm Charcoal Smoke Texture.png`, 887 × 1774, 1,545,385 bytes.
SHA-256: `ae188cac206be1bb90822f99ad1129433d871091c645d425e433d8324d83c231`.
The original remains untouched in the task evidence. The optimized derivative
is `storefront/public/cinematic-preview/menu-background.webp`, 12,432 bytes,
SHA-256 `8111815f8503d23e91b8465388e65afb84b9fe1f9bb9b213d38a8c374b81a308`.
This is the user's supplied texture, not a new generated replacement. The
Preview profile selects it with 15% dimming; no hosted restaurant setting changed.

## Focused evidence

- 101 Node checks pass: 46 focused reader/appearance checks plus 55 Home/content
  compatibility checks. The live-mode Next build and TypeScript pass.
- Disposable PostgreSQL 17.5/PGlite 0.3.14 runs 31 checks against the actual
  prepared migration and existing profile/content/media functions. Coverage
  includes strict shape/dim/media validation, old-writer preservation, reset,
  version/replay, usage/retract, same-source republish and unchanged menu/order
  admission. Executed migration SHA-256:
  `0c82a818ff0cd35386570347df42576d747396df94037bbe557d825f9a73e295`.
- Nine SQL-exported public profiles run through the actual local live reader,
  decoder, adapter and browser: legacy values, legacy Hero fallback, selection,
  older-writer preservation, whole-object omission, replacement, republication,
  unavailable media and clearing. Reloaded URLs and computed dim/color/font
  values are checked. Six open/closed/paused × ordering combinations remain
  source-accurate. Browser results contain no page errors or non-GET writes.
- Full 390 × 844 mobile and 1440 × 1000 desktop captures retain four categories,
  20 products and independent carousels. All visible product/footer images and
  fonts finish loading. Document widths equal viewport widths. The background
  layer and image span the entire measured menu through the footer, with a
  computed overlay opacity of 0.15 on both viewports.

Evidence: `appearance-sql-runtime-v5/results/report.json` and exported profiles,
`cinematic-evidence-v5/closeout-checks.json`, `capture-measurements.json`,
`04-desktop-menu.png`, and `05-mobile-full-menu.png` in the task workspace.
This extends the earlier 18-check/two-profile evidence in
[the v4 closeout](BIZBOT_STOREFRONT_CINEMATIC_001_CLOSEOUT.md).

The scratch SQL harness uses synthetic core tables, actor/rank, an older-v3
catalog projection and storage-object metadata. It runs the real eligibility,
retract/finalize and reference helpers, but uploads no image bytes. Flutter/Dart,
the complete Supabase pgTAP/Auth/RLS integration and real storage upload/download
remain unexecuted. Browser transport is test-only loopback, not hosted end-to-end
verification. No application dependency or hosted schema/data was changed.

## Rollout boundary

1. Deploy readers accepting the optional public appearance fields.
2. Apply the prepared migration only with separate hosted approval.
3. Publish the dashboard writer and enable its existing editor gate as approved.
4. Publish/select the image through the existing media flow, then save its dimming.

Preview branch updates are authorized. Merge, Production, hosted migration and
tenant-setting changes remain separate approval steps. The read-only preflight
found the prior Preview head `080d682743f8ae68f33b8e8ae9c842faa19d52fa`, unchanged
main `be579180d43958f716872dac22daf24ba7cc8c26`, and no path overlap with Claude's
unchanged payment PRs #370/#371. No payment or shared localization files changed.
