# BIZBOT-STOREFRONT-APPEARANCE-UX-002

Owner instruction: improve the post-PR380 Dashboard appearance/media organization and custom menu background, deliver an isolated Draft PR. No merge, production deployment or hosted operations in this task. Base: ad8c3caf1542770c2581630c7074f901bcd579dc.

Read-only report delivered before edits: selected backgrounds use published w960 with no upscaling. Current CSS paints them over the full menu document and changes to object-fit:fill on mobile. Fix the display geometry, not invented source detail. Existing small images remain resolution-limited. No schema, RPC, publisher, image recipe, dependency, public-cap or model change is required.

Acceptance: custom background keeps its ratio and viewport geometry at desktop/mobile sizes and after scroll; intro/inherited background, scene and dim0/15/80 remain compatible. Compact published-media previews show truthful dimensions and current use. Large settings fold without losing drafts, pending request IDs, source/tenant invalidation or focus isolation. Save/publication remain explicit and use the existing actions. Four pickers and Original/cutout workflow remain intact.

Cleanup audit: hide only the stored-for-later locale-default selector; retain its hydrated value and patch logic. Keep announcements, promo/story, primary/accent, text/button-text, font, theme, card-mode and motion: each has a real direct or conditional consumer (including dedicated search/order pages). Put the duplicate legacy welcome-text editor in a labelled compatibility group; retain fallback for old clients. Do not delete stored JSON/settings. Catalog combo types are outside this scope.

Verification: focused Flutter widget/state/focus/save/retry tests; Dashboard analysis; source and rendered responsive Storefront tests, typecheck/build/output budgets; unchanged required CI on final source; adapt the existing isolated real-service lifecycle to opening groups through visible controls. Actual merchant data is not edited for demonstrations. Capture local before/after screenshots with honest source-resolution limits. Independent review before delivery.

Excluded: payment/cart/order behavior, notification/printing/SEO activation, protected historical data and Claude's other trees. Each contributor uses a separate branch/worktree; root integrates scoped commits only. Existing compatibility and protected PR380 release evidence remains historical evidence, not fresh execution proof.
