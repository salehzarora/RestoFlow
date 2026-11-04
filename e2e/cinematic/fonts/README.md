# Exact Flutter fallback fonts for isolated CI

These files are used only by the cinematic integration runner's generated
Dashboard build. They are not Dashboard product assets or Storefront assets.
The test browser remains restricted to loopback origins.

Flutter 3.44.2 (`c9a6c484230f8b5e408ec57be1ef71dee1e77020`) CanvasKit loads
Roboto and Noto text fallbacks independently of `--no-web-resources-cdn`.
Blocking those requests left the actual CI Dashboard without rendered text and
repeatedly downloading fallback fonts. The supported `fontFallbackBaseUrl`
configuration points at a local, byte-identical mirror in this test build.
No font family, glyph, application repository or authentication path is replaced.

Original bytes were retrieved on 2026-11-03 from
`https://fonts.gstatic.com/s/` followed by each exact `path` in
[`../font-mirror.mjs`](../font-mirror.mjs). SHA-256 pins are enforced before the
assets and licenses are copied. Paths come from the pinned SDK's
`engine/src/flutter/lib/web_ui/lib/src/engine/canvaskit/fonts.dart` and
`font_fallback_data.dart`; the configuration is defined in `configuration.dart`.

Roboto is licensed under Apache 2.0; the included license is from the same
pinned Flutter SDK's `bin/cache/artifacts/material_fonts/Roboto_LICENSE.txt`.
Noto Sans Arabic, Noto Sans Hebrew and Noto Sans Symbols use SIL OFL 1.1; their
included licenses were obtained from the corresponding `google/fonts/ofl/`
family directories. Copies accompany the served fonts.

The integration receipt records original/generated-bootstrap fingerprints and
font hashes. It is evidence of this isolated test configuration, not a claim
that Production has acquired these local resources.
