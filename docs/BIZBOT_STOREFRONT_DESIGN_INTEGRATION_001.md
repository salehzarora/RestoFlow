# BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001

Local implementation and review record. No push, PR, merge, deployment or production operation is authorized by this task.

## Follow-up status

Owner status: **LOCAL_FOUNDATION_REVIEWED — VISUAL_AND_CONTENT_COMPLETION_PENDING**. Follow-up local review has an explicit **CSS_BUDGET_BLOCKER**; it is not ready for merge or deployment.
Preserve foundation commit `039a318404f1ed3b4d0c6655db9a0b9bad33f9d6` unchanged. This local follow-up continues the same Work ID; local tests and independent source approval do not constitute final visual/content acceptance. No push, PR, merge or deployment is authorized.

The section headed “Preserved foundation evidence” records the earlier006/003/003 lanes and their historical results. Its words “final” and “latest” refer to that foundation only. Fresh follow-up evidence is recorded separately below and in the new SHA-bound external receipt. Prior runs, images and reports remain untouched.

## Source and concurrency

- Branch: `feat/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001-approved-design`.
- Worktree: `C:/Users/saleh/Desktop/ClaudeAi/RestoFlow/worktrees/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001`.
- Base: `fe78bbcd4de5befb91c09bd9161380f151fc7c6b`.
- Final head, changed-file hashes, test totals and screenshot inventory are recorded in the external final receipt after the local commit; this document does not invent a self-referential commit SHA.
- Approved reference source: `5d71a7257840bfb12e57ceb9d40e873e0339b613`.
- Owner ZIP SHA-256: `b3e2f82e665cbace873a028fa897fa0d89c4bc16602f08a226993462de4cc68d`. All 43 manifest files verified before use. The URL presented a sign-in gate; the unchanged bundled reference was served locally.
- Evidence root: `C:/Users/saleh/.codex/local-config/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001`.

The initial read-only preflight inspected 161 registered worktrees: 81 accessible, 80 absent/prunable and explicitly **UNVERIFIED**. It did not prune, repair, reset, stash, clean or switch another checkout. The primary repository is the nested `RestoFlow/RestoFlow`; its stale main and owner untracked files remain untouched.

| Open work | Observed head | Boundary |
| --- | --- | --- |
| ETA #366, Draft | `672202aba654ca7355317bc284305fcf5ecc29e6` | No orders contract/controller/transport, orders i18n, ETA, SQL/Edge/POS/receipt or LiveRequestRuntime edits. Status changes are CSS only. |
| Claude payment #362, Draft | `96fd9597f5d2aa46152ea4359f59539e498d8306` | No payment/SDK/shift/source or reserved shared-document edits. |
| Claude payment #363, stacked Draft | `b787344a2caa237b9242e69fdbebbc1a70007461` | Preserve stack/ancestry. No retarget, rebase, merge or conflict resolution. |
| Printing #314 | `54346b37b35679c21248a64e40dcb3b0ca894673` | No overlap or changes. |
| Printing #315 | `4e8c81f6bd7249f3a44d1089c6253ad84df7f413` | No overlap or changes. |

The dirty instant-wake worktree has an Edge-file overlap with ETA, outside this task. Payment and ETA worktrees were clean when inspected. No inaccessible tree is claimed conflict-free. Full original metadata is preserved under `preflight-001/`. A bounded follow-up read-only refresh under `followup-001/preflight/` fetched remote main, checked the five named workstream heads and their accessible status, and retained82 reserved paths. Main remained `fe78bbcd4de5befb91c09bd9161380f151fc7c6b`; the five heads above were unchanged. No intended follow-up path overlaps those reservations. Absent/prunable printer aliases remain UNVERIFIED, rather than being declared conflict-free.

## Implementation scope

| Area | Owner for this task / change | Open-work overlap |
| --- | --- | --- |
| Home, HomeChrome, HomeParts, MenuParts, home CSS | Codex: approved split/arched Hero, sticky header/categories, real menu search, manager picks, food cards, content/contact/footer | None of the five PR path lists |
| Intro and LanguageMenu | Codex: derived welcome using the same Home primitives; native three-language disclosure shares flat header styling | No route, session or localization-contract change; both actual callers already used the compact trigger |
| Product CSS | Codex: 860px desktop 64/36 content/image split; mobile 94dvh sheet, option tiles, persistent action footer | Product logic left unchanged |
| Existing live cart aside + CartScreen/flow CSS | Codex: native cart dialog, thumbnails/Edit/Remove, existing quote and checkout guards; route totals outside scrolling lines | None |
| Theme, storefront dictionaries, contact icon | Codex: cream light surfaces, existing brand derivation/contrast rules, AR/HE/EN UI labels | No orders i18n or public contract changes |
| Request CSS | Codex: derived visual extension only | Semantic integration with #366 must be reviewed before a later merge; reserved runtime untouched |
| Tests/module-order/task report | Codex: replace superseded visual expectations; retain money/privacy/isolation/negative controls | Shared payment documents untouched |

The old September/October layout and #367 photo containment remain in Git history. The newly approved food-card `cover`, aspect ratios and positions supersede those covered visual expectations. The published image URLs and missing-image behavior remain authoritative.

`reference-site/app.js`, `commerce.js`, preview storage and menu JSON are not imported into production. The fixture comparison remaps public reference content into the existing local fixture types outside Git. No additional package, API/RPC, SQL, data reader or schema was introduced.

## Dashboard → public data → UI map

The existing path remains Dashboard authorized writers → `storefront_menu_v3` → strict decoder → adapter/types → presentation. Existing v1/v2/v3 contracts are unchanged.

| Design element | Existing authority / actual behavior |
| --- | --- |
| Restaurant name / identity | `display_name` → `tenant.displayName`; full logo uses contain, no universal Maps crop |
| Header logo | `logo_media_id` → published logo URL → `tenant.brand.logo` |
| Hero photograph | `hero_media_id` → `tenant.heroImage` only; no product-name or UUID inference |
| Hero heading/subline | Home text writer → `hero_headline` / `hero_subline` → `modules.campaign` |
| Announcement strip | `announcement_text`; absent when unconfigured/closed/paused; existing session dismissal preserved |
| Colors / mode / movement | `primary_color`, `accent_color`, `visual_preset`, `card_mode`, `motion`; existing sanitation and contrast remain |
| Kitchen picks/badges | `featured_item_ids` → `item.featured`; unavailable products excluded from picks; tags do not confer manager selection |
| Category buttons/counts | Served categories and canonical served items; no fixed four-category assumption |
| Product cards / details | Canonical name, description, image, price, modifiers, availability; no reference aliases applied to live names |
| Contact / location | `public_phone`, `public_city`, `public_address`; existing safe telephone helper; no customer/private-number fallback |
| Hours / service / state | Existing tenant hours/service projection; operational strip remains visible after the menu, before optional content |
| Decorative route/map | Illustration only; no coordinates, GPS link or location claim |
| Cart / checkout / statuses | Existing runtime, menu-version cart, integer money/quote, modifiers, private request identity/recovery and status truth |

The binding proof here is local: existing Home/featured/contact/public-projection tests, unchanged strict live decoding/adapter source, and synthetic independent-tenant renders. This task did not save merchant Dashboard data or perform a new production save→public-menu round trip. The earlier owner-reported Home text/phone saves remain historical evidence in the Resume ledger, not a new deployed-design acceptance claim.

### Bounded configuration gaps

These are **not completed** and are not filled with static React/JSON production data:

1. No explicit Hero-product relation, product caption, price or click target. The Hero remains non-product media. A separate contracted same-tenant relation is required before any such association.
2. No editor-controlled eyebrow/stamp/short brand alias/marketing coordinate/footnote fields. Reference claims/aliases are omitted rather than fabricated. The complete merchant logo remains visible.
3. `promo=null`, `story=null`, category `image=null` / `blurb=null` in the live adapter. Existing optional presentation remains conditional; absent content creates no fake offer/story.
4. No independent category marketing title or per-product English subtitle. Actual public names/descriptions are retained.
5. No authoritative drink/media-fit field in the public menu. The implementation does not guess from names, language, IDs or category counts. Generic cards use the approved food crop; the reference's drink-specific contain/four-column mode remains a separately contracted presentation-data gap.

These gaps need a small separate Work ID/contract/review for the affected writer/projection fields, not an unrelated payment/POS change. Do not claim that a preview fixture proves Dashboard controls exist for these fields.

## Preserved foundation evidence — commit039a3184

Reference/candidate use the same explicit public reference content, local fonts, selections, viewport, scroll and reduced-motion state. Candidate components/cart/product authority are unchanged by the harness; only copied fixture data/assets are replaced outside Git. AR/HE/EN, another tenant, dark/list and checkout/status are **derived extensions**, not invented reference screenshots.

Required viewport set: 320×844, 390×844, 430×932, 768×1024, 1440×1000. Side-by-side gallery and individual screenshots live under the external evidence root and are linked by the final report.

Residual differences are deliberate where no public content authority exists: Hero captions/stamp/marketing copy, category editorial text, preview subtitle aliases and optional dark editorial section. General logos are not cropped like the reference brand. Header language access remains. Accessible small-text/CTA ink remains contrast-derived rather than copying failing white-on-orange pairs. Large heading accent uses the accepted large-text contrast floor. Product choices remain explicit, note limits remain production limits, and real pricing/availability wins over preview defaults.

Tests are reported by actual current run, not by authored specs. The initial visual run found a mobile decorative-route overflow; the reference's final horizontal clipping rule was applied and the next physical-dependency run passed 16/16 cases. A dependency-junction experiment was denied by the existing exact worker-path fence before compilation; no guard was weakened. All runs and cleanup records remain preserved.

Independent review found and fixed native-cart → product handoff for pointer/Enter/Space, late focus restoration, and the `/` shortcut escaping an ARIA product modal. Actual browser tests cover these paths and same-line quantity replacement. The final receipt records the final reviewed source and tests after subsequent scoped adjustments.

The retained Home presentation is keyed by tenant slug and falls back to the first served category when a refreshed menu removes the selected category. Multiline merchant headlines preserve every line; only the final line receives the large accent treatment. Large Hero text uses a separate 3:1 contrast walk, so a pale tenant accent cannot copy the reference's raw orange rule without meeting contrast. Ordinary text and control ink retain their stricter existing floors.

The welcome route is a **derived extension**, not a matching-reference claim. It retains IntroGate, first-visit/per-slug session handling, deep links, the existing canonical tenant menu/search/language URLs, service truth and the visible Explore action. It now reuses Home's header/Hero/service styling. Native `details`/`summary`, 44px language control, locale names, plain cross-locale anchors, `lang`/`dir`/`hreflang`, active check and `aria-current` remain. The unused wide-trigger branch was removed after checking both actual callers. The two old CSS files remain preserved but unimported; source scanners and their negative controls were not relaxed.

The final reference capture completed **32/32 cases**, with exact committed CSP applied to both local renderers, zero skipped/unexpected/flaky cases and clean owned-process cleanup. Build ID: `ZU-uIF-N8Fnn7zgEyiSNc`. The final gallery contains **65 unscaled side-by-side comparisons** at all five required widths. Capture success verifies interaction/geometry assertions and complete evidence collection, **not** pixel equality. In particular, drink-card image size/fit and missing editorial metadata remain visible differences.

- [Full comparison inventory, source/output hashes and image dimensions](C:/Users/saleh/.codex/local-config/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001/visual-review-final-003/inventory.json).
- [390px Home: reference left, implementation right](C:/Users/saleh/.codex/local-config/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001/visual-review-final-003/compare-390-home-viewport.png).
- [1440px product/options](C:/Users/saleh/.codex/local-config/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001/visual-review-final-003/compare-1440-product-base-choices.png).
- [390px filled cart](C:/Users/saleh/.codex/local-config/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001/visual-review-final-003/compare-390-cart-filled.png).
- [390px drinks: explicit remaining presentation-contract gap](C:/Users/saleh/.codex/local-config/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001/visual-review-final-003/compare-390-drinks-menu.png).

The latest system-extension run completed **137/137 synthetic cases**, zero skipped/unexpected/flaky cases and clean owned-process cleanup. Coverage: 78 locale/width/content/theme/card-mode cases, six real fixture Pickup/cash Checkout → Review journeys without Send, 36 fixture status cases, six waiting-cancel Escape/trap/inert/focus-return cases, ten real Intro/session/language/deep-link/tenant cases, and one off-origin denial control. These are extensions of the design; they are not screenshots of reference states that do not exist. The retained 201 non-fixture source pins match after execution; only the exact reviewed copied fixture generator changes the scenario module and adds five synthetic SVGs. No fixture change enters the worktree.

- [Final extension results and limits](C:/Users/saleh/.codex/local-config/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001/extension-harness-003/evidence/summary.json).
- [Post-run source and 41 decorative containment checks](C:/Users/saleh/.codex/local-config/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001/extension-harness-003/evidence/ROOT-POSTVERIFY.json).
- [Independent tenant welcome extension](C:/Users/saleh/.codex/local-config/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001/extension-harness-003/evidence/en-1440-extension-tenant-b-derived-intro-first.png).
- [Arabic local checkout Review, no submission](C:/Users/saleh/.codex/local-config/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001/extension-harness-003/evidence/ar-390-review-local-cash.png).
- [Arabic fixture rejected status, not a private live-order proof](C:/Users/saleh/.codex/local-config/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001/extension-harness-003/evidence/ar-390-fixture-status-rejected.png).

The canonical default-Turbopack fixture lane is separate from the Webpack visual lane. The initial canonical attempt compiled but was stopped at the TypeScript child by the test boundary: pinned Next 16.3.5 sets exactly `TURBOPACK=auto`, which that boundary did not yet admit. Its failed receipt remains preserved. A separately reviewed fixture-only boundary admits only that fixed marker; other values, cloud variables and arbitrary commands remain denied. No application build config, budget or source guard was weakened. Final canonical output/budget results belong to the final receipt. Provider-shaped live/missing-source builds and remote GitHub CI are not claimed from this local fixture run; no push is authorized.

The next canonical run completed the default build, TypeScript, real loopback HTML/RSC snapshot and output audit. It exposed two real failures: CSS exceeded the unchanged limits, and one output assertion still demanded the superseded permanent Home aside. That assertion now separately requires the four Search frames and the four Home zero-count openers/no preopened dialog. Every cart-line/money/privacy assertion and the planted fabricated-cart negative controls remain. The performance correction consolidates the derived flow/request styling into single flat token-based rules instead of retaining old decoration beneath appended overrides. All 127 actual flow classes and all 97 request classes remain; no request/cart/controller/state logic was changed.

The final **canonical006** default Next/Turbopack fixture build and TypeScript check pass, followed by 37 captured HTML/RSC documents, 36 measured routes and **28/28 exact output tests**. All seven stages pass on the final 202 source pins and eight gate inputs. Maximum raw first-load CSS is **93,828 B**; worst Brotli is **13,972 B / 14,000 B**, leaving **28 B**. Raw CSS uses the pre-existing owner-approved `CSS-UI001-01` 100,000 B exception; original 70,000 B failures remain recorded. No new exception, budget increase, guard deletion or alternate compiler was used to claim canonical acceptance. This is narrow headroom: later CSS work must rerun the actual emitted budget gate.

| Verification | Command / local evidence under the evidence root | Actual final result |
| --- | --- | --- |
| Storefront unit/contract/source/theme/cart/phone/web-order tests | Pinned Node `--test tests/*.test.mjs`, from the isolated Storefront; `unit-ghost-final.log` | 387 PASS, zero fail/skip |
| TypeScript | Existing `tsc --noEmit` and canonical default build TypeScript stage | PASS; no application source/config/dependency bypass |
| Canonical build/output/budgets | Reviewed `ci-harness-006/launch-reviewed.ps1`; `ci-harness-006/evidence/summary.json` | All seven stages PASS; output 28/28; existing raw exception retained |
| Reference browser comparison | Reviewed `visual-final-003/launch-reviewed.ps1` | 32/32 PASS; 65 comparison pairs; 137 captured PNGs |
| Derived browser extensions | Reviewed `extension-harness-003/launch-reviewed.ps1` | 137/137 PASS; 41 decorative bounds checked |
| Deployment filter tests | Pinned Node `--test tools/vercel/ignore-build.test.mjs`; `deployment-filter.log` | 170 PASS, two explicit Windows/POSIX filename skips, zero fail (172 total) |
| Three-project filter matrix | Existing synthetic-Git proof; `three-project-filter-proof.log` | Seven scenarios × three selectors = 21 expected decisions PASS |
| Money guard | Git Bash `tools/check_no_float_money.sh`; `money-final.log` | PASS, including self-test |
| Secret guard | Git Bash `tools/check_secrets.sh`; `secrets-final.log` | PASS, tracked and non-ignored source |
| Whitespace/scope | `git diff --check` and explicit 27-file inventory | PASS; no reserved runtime, SQL, Edge, POS, payment, dependency or release changes |
| Remote GitHub CI, provider live/missing-source builds, hosted CDN | Not run; no push/deployment authority | UNVERIFIED; local fixture proof is not Linux/hosted proof |

The commands above describe completed local runs, not instructions to reuse a consumed harness namespace. Exact reviewed executable/source hashes and cleanup receipts remain outside Git. No dependency installation or version change was needed.

All earlier failures remain preserved. In visual002, 31 cases passed and one synthetic headline case failed because its test incorrectly demanded exactly one physical text rectangle per stored line. The independently reviewed correction permits normal wrapping while checking all rectangles, three stored spans, two explicit breaks, exact text, separation and final-span-only accent. Visual003 passes that stronger spatial check; visual002 is not rewritten as a pass. Extension002 also exposed long decorative tenant text spilling below the Hero. The final CSS constrains only the aria-hidden decoration to one clipped line, leaves the real identity intact, and passes 41 bounds checks plus a freshly inspected tenant-B image. A metadata-only postcheck initially used the wrong copied fixture path; it stopped before writing a receipt, then was corrected to the exact pinned generator path without rerunning a workload or changing source.

`request.module.css` supplies the existing fixture received/status/cancel views. The real private `LiveRequestRuntime.tsx` uses its separate unchanged `liveRequest.module.css`, plus the existing shared theme/flow controls. Its public rejection reason, private capability, refresh/recovery and future #366 ETA logic were not replaced by fixture status behavior. Precise private-status layout integration with the reserved runtime remains a coordinated follow-up; local demo screenshots are not live order evidence.

Security, money, privacy, decoder and authentication boundaries were not relaxed. The earlier incident-prone mock harness was not reused. Its production connectivity remains **UNKNOWN**, unchanged. The new fence is trusted-source loopback/process containment plus Chromium request/WebSocket denial, **not** an OS sandbox or proof of arbitrary browser background traffic.

No hosted operational readback is claimed from this local task. No production order, call, payment, print, secret/configuration mutation, migration, deployment, APK operation, registration, notification/Cron operation or protected-print replay occurred.

## Owner follow-up001 — display completion, local only

This follow-up changes only Home presentation, its existing locale dictionaries, focused tests, one pure suggestion helper and this task record. The shared data/ordering/API/SQL/payment/ETA/private-status/POS/printing paths remain untouched. The final local commit and source-byte hashes are recorded externally after commit; this document does not invent a self-referential SHA.

| Difference | Classification | Actual treatment / remaining limit |
| --- | --- | --- |
| “محتار؟ اختارلي!” | Fixed | Uses only the currently served, available items in the selected category; Kitchen Picks uses the existing manager-selected available subset. Search does not change category authority. No cross-category fallback, names/UUID inference or sales claim. Native pointer/Enter/Space opens the existing ProductSheet; no automatic add or submission. Empty pool disables the control with a localized explanation. Existing Runtime still owns validation, history, modifiers and focus. |
| Hero underline | Fixed | Reference double-curve SVG applied only to the final explicit headline line; saved text/line order is retained. Long text may wrap normally. No guessed split of a one-line merchant headline. |
| Header / identity / menu / search | Fixed, with intentional adaptation | Spacing, reference section/search wording and generic welcome are localized in AR/HE/EN. Full merchant logo, stored name/accessibility label, language access and service truth remain; no Maps-specific alias or crop. The generic translated welcome is UI copy, not a merchant claim. |
| Announcement rhythm | Fixed, with intentional adaptation | Symmetric decorative separators, spacing and alignment around one escaped, complete `announcement_text`; existing service visibility and slug-session dismissal remain. Mobile text stays12px and grows/wraps instead of copying the reference’s10px fragments or splitting free merchant copy. Newline fixtures test defensive rendering only; existing Dashboard control-character restrictions are unchanged. |
| Contrast / responsive behavior | Intentional functional adaptation | Keep derived readable CTA ink and tenant contrast floors, full logo and44px language access. Do not restore inaccessible white-on-orange merely for pixel similarity. Narrow layouts may wrap actions and merchant text. |
| Hero product name / price / link | Needs data contract | No inferred relation to the Hero photo. Proposed same-tenant/branch, same-public-snapshot product relation; canonical item data and existing ProductSheet supply facts/actions. |
| Drink / whole-image presentation | Needs data contract | No name/language/icon/UUID guessing. Current general photo crop remains; explicit per-item fit/category presentation is proposed. Existing missing-image behavior remains. This is a visible reference gap, not completed fidelity. |
| Merchant stamps / photo footnotes / promo / story / category content | Needs data contract; retained under#360 | Optional bounded merchant copy/media and complete nullable modules are proposed; no fabricated claims, offers, prices or reference copy. |
| Real private order tracking | Coordinated follow-up#366 | `LiveRequestRuntime.tsx` and its CSS/ETA contracts are unchanged in this round. Fixture status extensions do not establish private live-status compatibility. Coordinate semantic layout after#366. |

### Minimum content contract proposal — not implemented

The complete field-by-field review table is preserved outside Git at:
`C:/Users/saleh/.codex/local-config/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001/followup-001/content-proposal/CONTENT_COMPLETION_PROPOSAL_R2.md`
SHA-256: `9c7c9a6db8117860c49e940395de48909bd2a8f3af39804809112537769e8dc7`. V1 remains preserved unchanged at SHA-256 `4d448a93629b119e23540e0b655245ae06de6f4f7d4429fbbb3908d74cc0dd69`; R2 adds only an optional merchant section heading to the category proposal, retaining the canonical rail/catalogue name.
Its evidence map pins18 foundation source files. It is included in the attachable review bundle.

| Proposed minimum addition | Existing authority retained | Compatible null/default and safety |
| --- | --- | --- |
| Optional Hero product selector | Existing `hero_media_id`, Home copy and public catalogue | Null keeps current editorial Hero; same served snapshot supplies name/price/from/options/link. Deleted/unpublished/foreign/branch-ineligible product yields no relation or stale private ID. Missing product photo uses honest no-photo handling. |
| Explicit item image fit + category photo/cutout presentation | Published item images, canonical category/name/order and current photo layout | Inherit/photo preserves current layout; whole-image means contain/center without cover zoom. No classifiers derived from names. Missing images preserve fallback. |
| Optional merchant eyebrow≤60, stamp≤80, photo footnote≤120 | Existing merchant Home copy; generic UI labels remain translations | Blank→null, escaped plain text, manager+ covering scope, no generated claim. Null omits decorations or keeps generic welcome. |
| Category image/optional section heading≤80/blurb≤120; complete optional promo/story modules | Current null adapter slots and current owned published-media pipeline | Disabled/null remains current behavior; bounded copy, explicit media ownership/lifecycle, no independent discount price or implicit publication. |

All proposed writes require authenticated covering restaurant-manager authority, branch scope, validation/CAS/audit and public same-snapshot filtering. Public defaults must preserve existing profiles. A separately reviewed Work ID/contract is required for schema/RPC/API/shared-type changes, versioned projection alongside strict v3 readers, Dashboard controls and compatible rollout. No such implementation is included here. The full proposal details null/empty, missing/retracted image, deleted/unpublished/sold-out item, branch changes, price/options and tenant isolation.

### Fresh verification and evidence binding

The external follow-up receipt binds these completed local runs and images to the new local HEAD, preserved foundation039a3184 and basefe78bbcd. It does not grant owner visual approval. All50 current browser cases pass (32 preserved+18 new), zero skip/unexpected/flaky, build `bLeJYl7rAVl6mkECoSUCP`, clean owned-process cleanup. Native pointer/Enter/Space, repeat suppression, required modifiers, empty/sold-out pools, category/picks/search independence, Back/Forward, no automatic cart additions, one history entry, focus return and complete long/multiline announcement rendering/dismissal are covered.

Fresh System.Drawing composition created65 unscaled side-by-side pairs (reference left, implementation right), with159 original PNGs and29 separately classified local interaction/headline/announcement images. These record real local renders, not pixel equality or live customer behavior.

- [390px Home](C:/Users/saleh/.codex/local-config/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001/visual-review-final-004/compare-390-home-viewport.png) and [1440px Home](C:/Users/saleh/.codex/local-config/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001/visual-review-final-004/compare-1440-home-viewport.png).
- [390px product](C:/Users/saleh/.codex/local-config/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001/visual-review-final-004/compare-390-product-base-choices.png) and [1440px product](C:/Users/saleh/.codex/local-config/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001/visual-review-final-004/compare-1440-product-base-choices.png).
- [390px cart](C:/Users/saleh/.codex/local-config/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001/visual-review-final-004/compare-390-cart-filled.png) and [1440px cart](C:/Users/saleh/.codex/local-config/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001/visual-review-final-004/compare-1440-cart-filled.png).
- [390px drinks](C:/Users/saleh/.codex/local-config/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001/visual-review-final-004/compare-390-drinks-menu.png) and [1440px drinks](C:/Users/saleh/.codex/local-config/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001/visual-review-final-004/compare-1440-drinks-menu.png): remaining explicit presentation/content-contract differences.
- [All65 pairs and hashes](C:/Users/saleh/.codex/local-config/BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001/visual-review-final-004/inventory.json).

The fresh system-extension lane passes137/137 synthetic cases, zero skip/unexpected/flaky and clean owned-process cleanup, build `cRwlm-9Jo8gm9oJrr_1en`. It covers AR/HE/EN, widths320/390/1440, light/dark/grid/list/service/content states, isolated tenantB, Intro/session/deep links/language, fixture Checkout→Review without Send and fixture status/cancellation. These are intentional derived-system extensions with no matching reference for most states. They are not private live-order or Dashboard save→public-projection proof.

Post-run independent checks retain all203 worktree source pins. The visual copy has exactly four reviewed fixture-generator replacements (199 other pins unchanged); the extension copy changes only `src/source/scenarios.ts` (202 other pins unchanged) and adds five reviewed synthetic SVGs. These copied fixture changes do not enter Git. The exact post-run inventory and generator hashes are preserved with the independent review.

Root viewed the8 representative Home/product/cart/drinks pairs, long/empty suggestion states and independent-tenant/English narrow extensions. Visible residuals remain: drinks still use the generic three-column/cover mode rather than reference four-column/whole-image; category headings remain canonical, Hero product/price/stamp/caption relations are absent, whole merchant announcement wraps rather than becoming fabricated fragments, full logo/language access and readable CTA ink differ from the reference. Product/cart keep real production validation/controls instead of preview-only commerce/copy. Long header names retain the bounded two-line visual treatment and full accessible source label; full logo imagery is contained, not cropped. No final visual approval is claimed.

| Fresh follow-up check | Actual result | Evidence |
| --- | --- | --- |
| Storefront unit/contract/source tests |392/392 PASS | `followup-001/unit-007.log` |
| Default Next/Turbopack build, TypeScript, actual loopback snapshot,203 source/8 gate pins | PASS | `ci-harness-011/evidence/summary.json` |
| Canonical output/budget tests | **25/28; FAIL,61B over compressed CSS limit** | `ci-harness-011/evidence/output-tests-summary.json` + `measure-firstload.json` |
| Reference/behavior browser tests |50/50 PASS | `visual-final-004/evidence/results.json` + `summary.json` |
| Unscaled reference comparisons |65 pairs;159 original PNGs | `visual-review-final-004/inventory.json` |
| Derived-system browser extensions |137/137 PASS | `extension-harness-004/evidence/results.json` + `summary.json` |
| Remote CI, provider live/missing-source build, hosted/CDN, merchant save/display and physical acceptance | NOT RUN / UNVERIFIED | No push/deployment/production authority |

Earlier deployment-filter/money/guard results in the foundation section remain historical; this follow-up does not relabel them as new Linux CI. No deployment filter, dependency, ordering/money/phone/ETA/POS/print source changed. New exact scope/whitespace/secret evidence is recorded in the external receipt.

CSS reuses same-file local `flexRow` across23 base classes and `gridCenter` across11, with10 exact same-file aliases (44 compositions total). Late header/language/Hero rules are grouped with their components; equivalent650px overrides are grouped without changing their precedence. Local LTR remains unchanged; no checkout-CSS dependency or shared utility was added. Later responsive and alignment overrides retain their order. [CSS Modules composition contract](https://github.com/css-modules/css-modules/blob/master/docs/composition.md) requires leading declarations and local single-class selectors and exports both class names. This avoids repeating long generated selector lists; it does not delete functional styling. Compiled output, budget and fresh rendered proof are required separately.

Actual follow-up canonical measurements remain preserved:

| Lane | Default build / TypeScript / snapshot / pins | Output tests | Worst route Brotli | Overall |
| --- | --- | --- | --- | --- |
|007 | PASS |25/28 |14,093B | FAIL, CSS budget |
|008 | PASS |25/28 |14,133B | FAIL, CSS budget |
|009 | PASS |25/28 |14,079B | FAIL, CSS budget |
|010 | PASS |25/28 |14,065B | FAIL, CSS budget |
|011, final current source | PASS |25/28 |**14,061B /14,000B** | **FAIL:61B over limit** |

Canonical011 measured36 routes and37 actual local HTML/RSC documents on203 source pins and8 gate inputs. Maximum raw CSS is93,860B (HE93,858B), within the unchanged100,000B pre-existing raw exception. Three failed output tests report the same compressed-CSS gate through its budget/audit assertions; they are not three hidden functional failures. All failures remain failures. No new exception, increased budget, guard deletion, alternate compiler or automatic success waiver was used. The actual44 compiled compositions and helper/mobile order were independently checked.

The392 current Storefront unit/contract/source tests pass (`followup-001/unit-007.log`). The browser visual and extension lanes are separate local evidence and cannot change the canonical FAIL. They may complete to make the requested display review possible; no “CI PASS”, merge readiness, final visual acceptance or live behavior is inferred. Further CSS work must preserve these functional styles and pass the actual canonical gate before a later push/release proposal.

A read-only scan found no unused Home CSS class to delete. Proposed cross-file helpers, extra row compositions and unused fallback cleanup were not implemented merely to force a number; candidate estimates remain non-authoritative and preserved outside Git. No unrelated CSS, data contract or functional style was removed.

## Resume ledger

| Existing work | Evidence/status retained | Next step / owner |
| --- | --- | --- |
| #361 Home text | Merged/deployed; owner reported successful save/display | Retain current text writer/projection; owner edits merchant copy |
| #364 Contact/checkout copy | Merged/deployed; owner reported public phone save | Preserve public phone, hidden invalid contact, no persistent checkout number guidance |
| #365 Featured products | Merged/deployed; selector visible, owner was verifying save/display | Use manager selection; do not choose merchant products automatically |
| #367 Image fit | Merged/deployed at base `fe78bbcd` | Preserve historical record; new approved design supersedes crop in covered screens |
| Current design integration | Local worktree only; final receipt carries evidence/limitations | Owner/GPT review before any push or PR; no visual acceptance claimed from tests alone |
| Promo/story/category controls | Live adapter gaps remain | Separate narrow content contract/writers/projection review; retained under #360 |
| #366 ETA + receipt phone | Draft at observed head; backend/deploy/APK not included here | Preserve R2 contract, atomicity tests, compatibility and current owner/workstream; coordinate CSS/runtime integration later |
| Claude #362 → #363 | Separate stacked Draft payment work | Preserve merge-commit ancestry and later retarget/review process; no action here |
| #314 / #315 printing | Open, untouched | Their existing owner/review path; no print changes here |
| #360 complete journey / other tenant / visual acceptance | Local synthetic checks do not constitute full production/physical acceptance | Continue recorded roadmap and owner review; Issue remains open |

## Draft PR description / later release gates — not executed

Apply the owner's Oct22 approved Storefront design to the existing tenant-controlled storefront. Replace the old covered presentation while preserving canonical menu/cart/modifier/order behavior, published contact and manager-selected features. Add local reference comparisons, locale/theme/tenant extensions and keyboard/cart handoff regressions. Document the exact missing editorial/media contracts rather than shipping preview commerce or static merchant content.

Before any future push/merge: obtain authorization, refresh current main and all open heads/file reservations, review the exact final diff and semantic #366 CSS integration, run affected integration/required CI, and obtain the repository's exact-head human merge approval. No auto-merge or force push.

Before proposing any later Storefront release, independently verify the dedicated `bizbot-storefront` project `prj_Vc9MCCeYw96l5lYtbn9qbVQ7djap`, team `team_yynO6ARGc6VsRrAB69hOTTZy`, root `storefront`, actual `menu.bizbot.systems` binding and tested source. Do not reconnect Git, deploy a different project, or infer menu readiness from `resto-flow`/Dashboard results. No release action is part of this task.

## Owner follow-up002 — CSS gate closed; R3 remains a draft

This local continuation preserves foundation `039a318404f1ed3b4d0c6655db9a0b9bad33f9d6`, reviewed follow-up HEAD `7d837c5f9cb3099ed8ea12b377c30dc427f0ac3c` and base `fe78bbcd4de5befb91c09bd9161380f151fc7c6b`. The final local HEAD is bound externally after commit, without a self-referential source hash. Earlier reports, failed runs, captures and review ZIP remain preserved and attributed to their own sources.

The bounded pre-edit overlap check confirmed the own branch/tree clean and the five relevant PR heads/file inventories unchanged. The three CSS paths and this task document overlap none of the82 reserved paths. A later read-only scope appendix separately checked the focused `sf-home.test.mjs` update: also zero overlap. Claude's payment-B worktree now contains15 dirty shared-document paths; those, payment/POS/card work, printer314/315, notification/ETA overlap and all shared API/decision/security/money documents remain untouched. Missing/prunable printing aliases remain UNVERIFIED, with no cleanup or repair. A read-only `ls-remote` confirmed main still at the base; no fetch/reset/push was performed.

### Exact correction and equivalence limits

Production changes are confined to `checkout/flow.module.css`, `product/product.module.css` and `home/home.module.css`:

- Share the identical Flow stepper pseudo-element base declaration while keeping its RTL override list unchanged. The stepper remains LTR, with44px outward targets. Remove duplicate mobile cart90dvh and Home650px phone-hide/cart90dvh declarations only where the unconditional or900px rule already supplies the same value.
- Remove the three unread Product duration definitions; retain `--d-option`. Reuse identical same-file Product rules through local CSS Module compositions, including group/note heads, radio/check decoration and Full/Lively animation parents. Reuse existing Flow text/reset/layout declarations while retaining every field, row, selected/error, dim/centre and responsive override.
- For Product badge variants/free deltas and the Flow tall CTA, the component already always applies the shared base token. Local composition replaces only duplicated values; exact current-consumer unions were independently reviewed. Do not generalize this evidence to unsupported standalone variant markup.
- Remove the unread Product `--sf-motion` marker while retaining its empty Full composition target and all actual keyframes/animation/reduced-motion rules. Home already co-applies Full with Lively; its duplicate hover now composes Full. Compiled exports retain all127 Flow,53 Product and162 Home classes, all seven keyframes and all62 compositions. No cross-module dependency, functional declaration, translation, merchant content, ordering/price logic, private runtime or API/schema/shared type was changed.

The initial candidate was not sufficient. Actual results remain explicit:

| Local canonical lane | Build / TypeScript / snapshot / source pins | Output suite | Worst HE Brotli | Overall |
| --- | --- | --- | --- | --- |
|011, reviewed7d837c5f | PASS |25/28 |14,061B | FAIL, preserved baseline |
|012, owner A–C duplicate cleanup | PASS |25/28 |14,040B | FAIL |
|013, four Product aliases | PASS |25/28 |14,019B | FAIL |
|014, ten Flow aliases | PASS |25/28 |14,008B | FAIL |
|015, already-coapplied variant/base reuse | PASS |25/28 |14,003B | FAIL |
|016, final motion reuse/unread-marker cleanup | **PASS** |**28/28** |**13,998B /14,000B** | **PASS, all seven stages** |

Canonical016 measures all36 routes using the unchanged default Next/Turbopack build and per-response Brotli text/quality11 method, including every Hebrew route. Other affected routes measure13,988B; maximum raw CSS is92,926B under the unchanged pre-existing `CSS-UI001-01` raw exception. There are zero budget problems. All203 application and8 original gate pins remain unchanged through execution;37 actual local HTML/RSC/404 documents and direct owned-child cleanup are recorded. No compressor, budget, exception, output assertion or compiler was weakened. **Only2B compressed headroom remains**; later CSS changes must rerun the actual gate. In-memory estimates are preserved separately and are not build evidence.

### Fresh focused verification and visual limits

The final app source exposed one obsolete unit expectation demanding the duplicate Lively selector literally (unit005:391/392). Its failure is preserved. The narrow test correction requires the actual Full scale1.045, Lively→Full composition and reduced-motion reset, with five planted negative controls. Missing/wrong alias, missing/wrong Full hover and missing reduced reset must fail; all previous continuous-animation and motif guards remain. Final unit006 is **392/392 PASS**, no skipped/cancelled tests. The test is outside the203 application inputs and8 output-gate inputs, so it does not relabel a different app build as canonical016.

| Fresh local evidence | Actual result | Scope |
| --- | --- | --- |
| `followup-002/unit-006.log` |392/392 PASS | Current unit/contract/source tests, including strengthened motion guard |
| `ci-harness-016/evidence/summary.json` and `output-tests-summary.json` | Seven stages PASS;28/28 | Original fixture, all36 routes, unchanged gates |
| `visual-final-005/evidence/summary.json` |58/58 PASS; zero skip/unexpected/flaky; cleanupErrors empty | Preserved50 cases plus8 AR/EN650/651/900/901 header/phone/native-cart geometry and focus cases; build `osh1lQ7C88EKWSC0DlnTF` |
| `extension-harness-005/evidence/summary.json` |141/141 PASS; zero skip/unexpected/flaky; cleanupErrors empty | Preserved137 cases plus4 AR/EN390/1440 required ProductSheet/head/cart/quantity/Edit/focus and LTR pseudo-target cases; build `sskvJJeTbX9KpyXsdSPue` |
| `visual-review-final-005/inventory.json` |65 fresh unscaled pairs,175 original captures including45 unpaired interaction/breakpoint images | Reference left, local fixture right;16px gap/40px label band. No old images relabelled as new |

Root inspected current390/1440 Home,390 ProductSheet/drinks and1440 filled-cart pairs. These confirm new evidence collection and preserve the visible residuals; they do not establish pixel equality or owner visual/content approval. Language/status/full-logo/contrast adaptations remain; Home product name/price/link/stamp, editable title emphasis/break, explicit drink fit/cutout grid, structured optional announcement segments and merchant promo/story/category controls remain unimplemented content-contract work. Current full announcement text wraps instead of being guessed into reference fragments. ProductSheet/cart retain real required choices, canonical data, edit/keyboard/focus behavior and production copy rather than preview-only commerce controls.

### R3 proposal and resumption

External draft `followup-002/content-proposal/CONTENT_COMPLETION_PROPOSAL_R3.md`, SHA-256 `4eccad1a5d1241e2f66a9834085b9faea2c6ba636cd7f347ee78a899eb1e0da4`, belongs to proposed `BIZBOT-STOREFRONT-CONTENT-CONTRACT-001`. V1/R2 are unchanged. Independent review approves it **as a reviewable draft only**, not an adopted contract or implementation authority. It defines:

1. Optional bounded highlight/break metadata bound to the exact saved Hero text, retaining control validation, null fallback and atomic reset on text change. The real editor cannot save the synthetic newline used by existing visual fixtures.
2. A closed category/item promotion target, same-snapshot authority, invalid-target handling and real enabled CTA acceptance; Dashboard data alone is insufficient.
3. Explicit editorial/item Hero mode and image/fact precedence, with honest missing-photo handling and no mismatched product image/name/price.
4. Separate item→category→default image fit/layout, complete-image crop/zoom reset, retained list/grid authority, cutout4/3/2 at900/650 and explicit mixed-result behavior.
5. Optional bounded announcement segments with clear priority; absence preserves every word of the existing wrapping free text.

The draft retains tenant/branch/manager/ACL/RLS/CAS/audit, owned published-media lifecycle, canonical price/options/availability and strict versioned public projection alongside unchangedv3. Proposed ownership/overlaps and future acceptance are recorded; no SQL/RPC/API/Dashboard/shared-type or reserved shared-document implementation is included. #360 remains open for remaining controls, content, full journey/multi-restaurant and owner visual acceptance. Live private tracking stays coordinated with #366; no ETA/LiveRequestRuntime changes enter this follow-up.

The portable review package contains full sources, complete patches (including reviewed7d→newHEAD), actual before/after36-route measurements, fresh images, R3, independent reviews, updated overlap/resume evidence and hashes. The external final receipt binds these to the final local commit and clean tree. Local tests do not establish remote CI/provider live/CDN/hosted behavior, current production holds readback or physical acceptance. No production order, call, print, notification/Cron, migration, deployment, APK or device action occurred; no push/PR/merge is authorized. Operational protections are preserved by no changes. The earlier incident's connectivity remains UNKNOWN_UNCHANGED, and the old incident-prone harness was not reused.
