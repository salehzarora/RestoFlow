# BIZBOT-STOREFRONT-SCENE-SCROLL-001

Owner-authorized presentation follow-up to merged PR382. Base main0fe8ef803882467c40e653d22e176f6a0b56b5fd. New isolated branch; keep the new PR Draft. No merge, Production deployment, merchant write, SQL/API/publisher/recipe/model/Dashboard/payment/order/POS/printing/SEO change.

## Demonstrated cause and correction

The custom and inherited menu photographs used viewport-fixed100svh boxes, so the lamp remained stationary. Centered cover also cropped the upper landmark away at desktop widths. The menu now anchors the same stable100svh cover box at the document top, horizontally centered/top-aligned. Its image ratio and existing bg2560/w960 descriptors, immutable URLs and cover-aware sizes are unchanged. Scrolling changes image viewport coordinates; returning restores them. No full-document photo enlargement, repetition, parallax or viewport/scroll listener was introduced.

Only the home/menu main explicitly fills100dvh. Its full-length decorative wrapper provides a token-derived scene underlay; the artwork's bottom fades into this continuation. Small-viewport artwork sizing remains independent of browser chrome's dynamic height. Intro/welcome retains its existing fixed photograph and layout. Root/body coverage, sticky header/category rail and native dialog scroll locking remain intact. The footer omits only a decorative Hero URL identical to the active menu scene, preventing the same lamp from being painted twice; a distinct editorial footer image remains.

The existing HomeChrome announcement markup, merchant copy, locale/bidi isolation, translated close button and per-tab/per-slug dismissal are unchanged. A defined dark translucent surface, readable light theme ink, accent border, modest corners and content-aligned gutters replace the weak tint strip. Long text wraps rather than clipping.

## Verification and boundaries

The initial runtime source74f8eaf6 passed472 Storefront unit tests, TypeScript,271-file input audit, real fixture-mode server build,36-route snapshot and31 output tests. Output3,634,562 bytes; worst-route CSS59,189 raw/11,915 modeled Brotli; two font preloads67,816 bytes. Existing limits remain unchanged with zero exceptions. These are local initial-source results; final-source CI and review must be linked in the PR before handoff.

Focused browser evidence uses the exact authorized public419×744/12,520-byte lamp derivative, SHA25600cce46ea0a702e0f72a3d63438e2afc1c1571f8f670a1adfe33637b48ab2cd2, with identical baseline/candidate settings in an isolated real Next application. It is not a merchant private original, an image-quality improvement or a production setting change. Before/after top/middle/footer/return sequences distinguish fixed from document-anchored artwork. Chromium and native local WebKit exercise repeated viewport-height transitions, rotation, short filters, footer/cart scroll restoration, multilingual announcement wrapping/dismissal/tenant isolation, sticky categories, carousels/products, dim0/15/80, proportional rendering and actual responsive resource bytes/selection. Keep resource/dimming/budget checks when replacing obsolete fixed-coordinate assertions.

Physical iPhone toolbar behavior: **NOT_RUN** without a legitimately available device session. Desktop WebKit/resizing proves page geometry, not actual Safari chrome. The three iPhone reference screenshots were absent from the supplied text attachment; their local paths were requested. Do not claim a match to unseen screenshots or a reproduced physical-toolbar root cause. No page-owned uncovered band was found in the initial native-engine resize probe; the explicit home coverage and continuation are verified separately.

The consolidated visual packet and full source-bound results are kept with the execution evidence and linked from the Draft PR. Stop at the reviewed candidate.
