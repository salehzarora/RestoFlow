# BIZBOT-STOREFRONT-CONTINUOUS-SCENE-001

Owner-requested background-only follow-up to released PR383, based on main1f82bcef96e0e3e03cc19efa6bd4ebe142d24e1a. The new acceptance explicitly replaces the earlier one-viewport photograph followed by a plain underlay: photographic detail must remain visible through the entire menu wrapper while scrolling with the document.

## Change

Home supplies published category/item counts to MenuBackdrop. Its existing lead image, native src/srcset/sizes, proportional cover, top alignment and document scroll remain. A decorative native-HTML grid continues the lower part of the same selected photograph through the wrapper. Alternating vertical reflection matches the strip edges without repeating the lamp. CSS rounds track heights to whole pixels; a small overlap is the fallback where round() is unsupported. No client code, scroll/resize listener, canvas, generated/re-encoded asset or external service was added.

Strip count is bounded at512 and selected from fixed tiers. Larger admitted catalogues get shorter crops rather than one massively enlarged background. Integer track minimums keep short/filtered pages from compressing the texture into dense bands; excess tracks clip inside the wrapper. The image box and64px bottom inset sample the lower half and exclude the selected lamp file's physical dark bottom edge. This is a geometric continuation, not semantic subject recognition for arbitrary uploaded photos.

All strip images retain the lead's identical responsive source attributes, so native browser selection/caching reuses one immutable candidate. Shared dimming covers all photographic paints once. The inherited Hero and reference-dark treatments remain available. Direct-child selectors keep the shared Intro photograph unchanged. The existing announcement, navigation, slider, footer, cart and ordering components are not edited.

## Evidence and verification

Verification compares the same authorized419x744/12,520-byte public lamp file with identical synthetic15% dim in real Next renders. Image-hidden diagnostic controls leave foreground/theme intact and prove that middle/footer samples contain actual photo detail; the released baseline fails these samples while the new renderer passes. The tests also check source crop, reflected joins, first paint without JavaScript, viewport/filter/cart restoration, multilingual announcement, native source selection/decoded hashes and one image response.

The admitted100-category/500-item landscape case exposed the former64-strip cap enlarging a photo to roughly3069px while selecting960. On corrected runtimec42d62f2 the same approximately69,500px document uses512 short strips, needs844px and fetches one verified960x720/111,406-byte file. Independent Chromium/WebKit probes cover the footer. On this maximum fixture, raw complete HTML increased875,931→1,582,098 bytes; estimated local Brotli q5 increased15,017→17,309 bytes. These are local fixture measurements, not hosted transfer bytes or phone performance guarantees. Small-menu tiers and client modules remain unchanged. Native one-file selection remains bounded by the published manifest; no claim of universal pixel-for-pixel DPR detail for every artificial wrapper/aspect combination is made.

Scoped runtime review and source-bound capture/byte/pixel receipts are retained in the execution evidence. Final-source normal/full integration CI and exact-source Preview results belong in the PR handoff. Existing output, CSS, JS, font, input, security and money limits must pass without new exceptions.

## Boundaries

No merchant background/settings/media were changed or republished. No private original was fetched, missing detail recovered, source photo replaced, SQL/migration/Edge/publisher/model/Dashboard/payment/order/POS/printing/SEO operation introduced. Protected history and concurrent work remain untouched. Desktop Chromium/WebKit and responsive viewport checks are not physical iPhone acceptance. Keep this new candidate Draft for review; the earlier PR383 release approval named a different immutable head.
