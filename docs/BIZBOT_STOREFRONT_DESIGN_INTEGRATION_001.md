# BIZBOT-STOREFRONT-DESIGN-INTEGRATION-001

Local implementation and review record. No push, PR, merge, deployment or production operation is authorized by this task.

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

The dirty instant-wake worktree has an Edge-file overlap with ETA, outside this task. Payment and ETA worktrees were clean when inspected. No inaccessible tree is claimed conflict-free. Full metadata and exact reserved-path inventory are preserved under `preflight-001/`.

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

## Visual evidence and verification

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
