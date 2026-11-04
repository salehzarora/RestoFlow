# Rubik, self-hosted

The unchanged Latin, Arabic, and Hebrew variable woff2 subsets each retain
weights 400–900, their existing disjoint Unicode ranges, and font-display: swap.
No metric-adjusted local fallback or third-party font service is used.

`rubik.module.css` declares all three faces and the existing `--sf-font-*`
variables. The browser fetches an on-demand face when its glyphs are needed.
`rubik.ts` references the same files through statically analyzable asset URLs;
Next fingerprints each source once for both CSS and React DOM resource hints.
The route calls the helper while rendering, so CSS chunk merging cannot add
another script's font preload.

| Root | Preloaded | On demand |
|---|---|---|
| `/`, `/ar`, `/en` storefronts | Latin, Arabic | Hebrew, including ₪ |
| `/he` storefronts | Latin, Hebrew | Arabic |
| Platform pages and unknown/404 | Latin | Arabic and Hebrew |

Latin owns spaces, digits, and punctuation. Arabic remains preloaded for
English storefronts because merchant content may be Arabic. The shared
stylesheet preserves every language's glyph coverage without extra preloads.

Previously separate next/font preload/on-demand calls emitted duplicate
Arabic and Hebrew binaries. BIZBOT-STOREFRONT-CINEMATIC-001B removes those
41,816 duplicate bytes and decouples preload policy from the CSS chunk graph.
The output tests check exact font bytes, one emitted copy per subset, correct
per-route preload sets, and the unchanged two-preload/120,000 B limits.

Alexandria remains optional and on demand. Its unchanged font and license
remain in `src/ui/storefront/fonts/`, beside the CSS consumer. The approved
choices remain `rubik`, `alexandria`, and `system`; Latin/Hebrew fallbacks
remain available with Alexandria.
