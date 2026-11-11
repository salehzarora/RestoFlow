# BIZBOT-STOREFRONT-MOBILE-ORDERING-UX-002 — local implementation

Owner-approved implementation scope (10 November 2026): implement the accepted light/dark and finger-follow mobile proposal in an isolated worktree, including the explicitly approved optional branch-content setting contract. The subsequent source-reconciliation authorization permits a normal commit/push and one Draft PR with required CI. Merge, deployment, hosted SQL and merchant writes remain prohibited.

Base: `46612618512b4a586eafdde1c153a63a6c8d92de`. Dedicated contract work: `BIZBOT-STOREFRONT-SITE-THEME-001-API`, documented separately in `BIZBOT_STOREFRONT_SITE_THEME_001_API.md`.

## Presentation boundaries

- Home/Intro and independently rooted Search/Request adopt the new palette only for explicit `siteTheme`. Missing/null retains each renderer's legacy theme semantics; new ordering layout does not infer an opt-in.
- `buildSiteTheme` retains raw merchant colors and selects legible presentation ink on actual copy/field/accent surfaces. Explicit light uses white surfaces and omits decorative scene painting without clearing selected media/dim. Dark returns to the same retained data. Neutral light CSS fallbacks remain readable before hydration; subsequent ThemeScope CSSOM supplies the actual brand tokens.
- `JourneyAppearance` adapts cart/details/review. Its explicit payment early return uses the old tokens and root without journey styles. Shared `flow.module.css`, `flowParts`/FooterCta, PaymentScreen and financial/validation/submit/transport code remain unchanged.
- ProductSheet consumes real items and modifier groups, with phone-sized controls and one modal scroll owner. Notes resize on value, fulfilment remount and width changes. No demonstration data, mock send or prototype pricing logic is part of the application.
- Category carousels retain keyed image nodes, independent selection, RTL/LTR and native vertical scrolling. Horizontal motion is bounded to one selection and release does not open/add a product. Reduced motion and ordinary arrow transitions are preserved. All animation work remains separate from centralized tenant theming.

## Local acceptance and limits

Detailed receipts, screenshots comparing the real application with the accepted model, device-size geometry checks, strict contract/tenant/CAS tests and independent reviews live outside the repository in `release-evidence/STOREFRONT-MOBILE-ORDERING-UX-002-IMPLEMENT-20261110`.

The local display harness uses the existing frozen anonymous public menu DTO and test contact data, plus an explicitly synthetic second brand. Browser order writes are blocked. The owner preview adds the unchanged committed CSP from `storefront/vercel.json` and a stricter `connect-src 'self'` policy outside application code. Review ends before submission. It is not a live merchant configuration or production-order acceptance test.

Local SQL uses a new synthetic database and a schema-only dependency baseline; no production data is cloned. It is not proof that every main migration or the full CI database suite ran. Physical iPhone/IME acceptance and final required CI/output budgets remain release gates, not silently waived.

Source reconciliation corrects the previous report's attribution: base46612618, preserved candidate tree7e9eea17, the candidate worktree and the exact source/render copies all declare and lock Next16.4.3. The old default checkout at556136f1 declares and locks16.3.5, before security commitf016c669. It is a distinct source context, not a verified manifest/lock mismatch in this candidate. The earlier read has no path receipt proving how the contexts were confused. No dependency or lockfile change is justified or included. The original report and candidate are preserved; exact Git blobs, raw file hashes and runtime paths are recorded in NEXT-FORENSICS.json in the source-reconciliation evidence directory. The existing local build used Node24.22.1 and Next16.4.3; clean installation/build evidence is recorded separately and must not be inferred from that existing installation.

## Future rollout, not executed

Review the exact new migration and coordinate its migration-history/baseline impact with Claude before any hosted operation. Install backward-compatible server projections/validation first without opt-in writes, verify old/current clients, deploy the reader/renderer and Dashboard, and then permit deliberate merchant saves. No backfill or image publication is required. Never change `visual_preset`, scene selection, saved media or other branches to manufacture the new mode.

The full merge checks remain enabled. This candidate does not authorize modifying payment guards, shared configuration, CI, aliases or deployment protection. The unchanged historical cinematic migration-sequence proof rejects the new successor; merely omitting this migration from its historical plan would not supply the new v8/v4 boundaries needed by real-service acceptance. A reviewed integration-plan extension and migration-history/baseline coordination are explicit merge/application blockers, not waived assertions. See BIZBOT_STOREFRONT_UX002_SOURCE_RECONCILIATION.md for the handoff and current coordination status. Preserve Claude/Z-Credit, protected historical data and625 holds; no POS/alert/printing/SEO work is included.
