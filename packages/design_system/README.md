# restoflow_design_system

Shared **themeable UI foundations**. Flutter package.

Per [ARCHITECTURE.md](../../docs/ARCHITECTURE.md) section 3 this package owns the
shared theme, design tokens, and (later) RTL/LTR-aware layout primitives
(DECISION D-014).

## Public surface
- `restoflowBaseTheme({Color seedColor, Brightness brightness})` — a seeded
  Material 3 `ThemeData` with consistent app-bar, card, button, chip, and
  divider styling. Defaults to the brand seed (light).
- `kRestoflowSeedColor` — the brand seed colour (the BIZBOT Emerald primary).
- `BizbotBrand` / `kBizbot*` — the OFFICIAL BIZBOT palette (see below).
- `RestoflowBrandMark` — the official BIZBOT symbol, optionally locked up with
  the official wordmark artwork (`wordmark: BizbotWordmark.latin`) or a
  localized product name + tagline.
- `RestoflowSpacing` — 4-point spacing scale (`xs`…`xxl`).
- `RestoflowRadii` — corner-radius scale (`sm`, `md`, `lg`, `pill`).

## Deferred
Richer shared widgets and bidi (RTL/LTR) layout primitives land in later UI
tickets. Brand colour is data-driven by the seed; direction is handled by the
localization delegates, not the theme.

## BIZBOT official visual identity (2026-09-05)

The platform identity is the owner's official BIZBOT identity board:

| Role | Colour | Token |
|---|---|---|
| Foundation / Charcoal | `#1F2937` | `kBizbotFoundation` / `BizbotBrand.foundation` |
| Primary / Emerald | `#059669` | `kBizbotPrimary` / `BizbotBrand.primary` |
| Highlight / Mint | `#A7F3D0` | `kBizbotHighlight` / `BizbotBrand.highlight` |
| Support / Light Neutral | `#F4F6F5` | `kBizbotSurface` / `BizbotBrand.surface` |

- The legacy `kRestoflow*` tokens and the `RestoflowBrandPalette` fields keep
  their names (they are consumed across four apps) but are re-valued onto this
  palette: `primaryNavy` is the Emerald primary (Mint on dark surfaces),
  `accentOrange` is the high-emphasis accent (Charcoal on light, Light Neutral
  on dark), `primaryNavyContainer` / `accentOrangeContainer` are the Mint bed.
  Derived functional shades (`kBizbotPrimaryDeep`, `kBizbotFoundationDeep`,
  `kBizbotFoundationSoft`, `kBizbotHighlightSoft`) exist only for hover/pressed
  partners, dark canvases and quiet washes — never as decoration.
- Semantic status colours (`RestoflowSemanticColors` success/warning/danger/
  info), KDS urgency, chart/category palettes and merchant/device themes are
  NOT part of the brand palette and did not move.
- Brand artwork ships as three bundled PNGs under `assets/brand/bizbot/`
  (symbol, Latin wordmark, Arabic wordmark), generated from the pinned owner
  masters by `tools/brand/generate_bizbot_official_icons.py`; the same script
  produces every favicon / PWA / Android launcher icon. Hashes are recorded in
  `tools/brand/BIZBOT_BRAND_ASSETS.md`. The identity board is a reference sheet
  only and is never bundled. The retired VEYRO symbol stays unreferenced under
  `assets/brand/archive/`.
- The compact in-app tagline stays the localized `authBrandTagline`
  ("POS & Operations"); the board's marketing line is exposed as
  `BizbotBrand.marketingTagline` for landing/marketing surfaces only.
- Contrast (WCAG): Charcoal on Light Neutral 13.5:1 · white on Emerald 3.77:1
  (large text / UI components) · Emerald on Light Neutral 3.47:1 (large text /
  icons; body-size brand text uses `kBizbotPrimaryDeep`, 5.05:1) · Charcoal on
  Mint 11.4:1 · Mint on white 1.28:1 (a highlight bed, never text).
