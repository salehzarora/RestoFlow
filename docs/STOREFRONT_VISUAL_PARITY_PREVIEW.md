# Visual parity review Preview

The existing isolated `/s/sf-design-preview/menu` route now defaults to the explicit
`reference_dark` treatment. `?scene=legacy` and `?scene=reference` compare the same
menu, photographs, background, dimming (15), font, colors, and layout. Only the scene
selector differs. Other values, repeated values, and missing values use reference.
The same comparison is available under `/ar`, `/he`, and `/en`; menu language links
retain it. Navigation to other screens uses the default reference treatment.

These routes reuse the shipped Storefront renderer and remain dynamic, noindex,
browse-only, and isolated from live tenant/cart namespaces. They are available in
Vercel Preview or explicit local `STOREFRONT_SOURCE=fixture SF_DESIGN_PREVIEW=1`
mode, and remain inaccessible in Production. The live v6 migration is not required
to view this captured review dataset. No SQL or merchant setting is changed.

## Photograph provenance

The prior cinematic Preview's 16 generative cutouts are **not used** by this review
profile. They remain in their previous paths for historical work. The profile now
uses 20 byte-identical copies of the original public URLs already recorded in
`runtime.snapshot.json`, captured on 2026-11-04 into
`public/cinematic-preview/originals/`. Their source URL, SHA-256, byte count, and
dimensions are recorded in `product-sources.snapshot.json`; tests verify each copy.
Total: 524,246 bytes; largest: 46,612 bytes. These are published derivatives, not
private original uploads. Their limited resolution cannot establish original
capture quality or accepted background removal.

The independently selected Welcome cover and menu background remain unchanged.
The warm smoke background is the existing optimized user-supplied texture. The
comparison demonstrates scene treatment with identical assets; it does not claim
pixel parity with a reference containing different photographs.

## Responsive source verification

`tests/browser/storefront-product-sources.mjs` renders the actual ProductCarousel
with its shipped CSS and observes Chromium `currentSrc`. Controlled image sizes
cover mobile/desktop and the 365/650px breakpoints, DPR1/2/3, portrait/square/landscape/
wide shapes, and active/side slides. It checks contain fit, no blur, and the selected
resource against the measured painted image size. The hint includes actual page
gutters, the carousel width cap, and the side-slide scale. Legacy items without
validated variants keep their existing source.

The optional absolute `SF_PRODUCT_EVIDENCE_DIR` reads a local `manifest.json` of
the independently derived burger original/provisional candidate c4 copies and
captures same-source w480-versus-responsive comparisons. This is local rendering
evidence, not a Dashboard save/publish journey. The recipe and quality ladder are
unchanged. A 600px input gives a 480px copy and a native 600px w960 copy, not an
upscaled 960px image; DPR requirements beyond that native size remain capped.

The actual service journey is separately defined in `e2e/cinematic/dashboard.spec.ts`.
Its Actions-only gate, timeout, Storage/publication checks, and source-byte checks
remain in force. Local Preview and controlled source tests do not replace it.
