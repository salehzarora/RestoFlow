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
profile. The 20 previous product files are preserved byte-for-byte in
`docs/visual-references/PR379-cinematic-preview/`, outside deployed static assets,
with a SHA-256 manifest and their recorded individual treatments. The profile now
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

## Static asset budget

The first snapshot retaining both historical products and the new source copies
measured 4,673,899 bytes against the unchanged 4,194,304-byte ceiling. Its only
output failure was total size; JS, CSS, font and individual-file budgets passed.
The measured overage was 479,595 bytes. The bounded remedy archives exactly the
20 unused prior product files, preserving every byte and their history. Cover,
logo and menu texture remain in place; current original-photo copies stay local.

After archival the final local snapshot measured 3,636,170 bytes, leaving
558,134 bytes below the same ceiling. Build, typecheck, input audit, all 468
Storefront tests, all 31 output tests, and output/first-load audits passed.
The entry route's first-load JS measured 577,154 bytes raw and 154,308 bytes
Brotli; the worst routes measured 681,257 bytes raw and 183,958 bytes Brotli.
Worst CSS measured 58,668 bytes raw / 11,808 bytes Brotli, and font preloads
67,816 bytes. All limits passed without new exceptions. These are local measurements on the
frontend change, not hosted transfer or final integrated CI results.
