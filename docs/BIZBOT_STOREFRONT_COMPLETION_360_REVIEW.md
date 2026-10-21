# BIZBOT-STOREFRONT-COMPLETION-001 — actual design comparison

Owner roadmap: [Issue #360](https://github.com/salehzarora/RestoFlow/issues/360).
Comparison baseline: `e9aec5405c5a9109458a8377111e75d80b9f6b1b`.
First implementation contract: [Home content](BIZBOT_STOREFRONT_HOME_CONTENT_001.md).

## Reference and actual website

The existing local `RestoFlow/Mobile app design project/BIZBOT_STOREFRONT_DESIGN_HANDOFF`
contains the approved September 20 handoff: 61 files, 11 screens, 36 PNGs.
The existing October 13 download is identical at every one of those 61 relative
paths and hashes; it is not a newer design. Its ZIP SHA-256 is
`2beccfbfd96b41cae1def82940cbec44f4b247b46783b78d9884aeb4078ef953`.
No design files were recreated or modified.

The actual public Home is `/s/mapsburger/menu`; `/s/mapsburger` is Intro.
`menu.bizbot.systems` resolves to the separately controlled `bizbot-storefront`
project, deployment `dpl_4vqyevAzDsNrCaP5qru4LyQFWgPj`, source
`b79c8907affadd2878c289e4cae8644170785738`. Its Storefront, Dashboard, profile and
migration inputs have no diff from the comparison baseline. Overall Git SHAs
being different does not prove the deployed Storefront source is different.
No project reconnection or deployment was performed.

Sixteen side-by-side PNGs are preserved outside worktrees under
`evidence/BIZBOT-STOREFRONT-COMPLETION-001/comparisons/`: reference left, actual
website right. Their manifest SHA-256 is
`3bd1516817bb09fc90d006cac04bfad395ef5688d2e1a9b14f4b55bcf3090669`.
Original pixels are not cropped; uniform display scaling and differing
theme/query/product/cart states are explicitly labeled. These are visual
comparisons, not pixel-parity or physical acceptance claims.

Ten captures have durable capture/request metadata. Six additional actual
product/cart/checkout/review PNGs have direct hashes, dimensions and filesystem
timestamps; their capture UTC is unknown. GET/HEAD-only interception and no
Submit for those six were observed in the session, not preserved as a network
trace. Their filled contact fields are synthetic browser-local input. No
production request was submitted. Received/status captures were not fabricated.

## What is missing, and what already exists

| Area | Actual observation | Classification |
| --- | --- | --- |
| Hero/header | Real saved media/name differ from demo; headline falls back to tagline/name and has no subline. Two 44px controls plus a 6px gap exceed the original 84px header side column. | Missing content authority plus a narrow layout defect; preserve real merchant text/media. |
| Announcement/promo/story | Components exist, but the live adapter supplies null. | Data/editor gaps, not missing page architecture. First slice adds announcement only; promo/story remain later. |
| Category/featured rails | Real categories use icon fallback and items have no live featured flag. | Additional public data/editor mapping required; do not invent photos or rankings. |
| Product | Required size selection enables Add and updates the local price. Sheet, options, group badge and footer exist. | Existing implementation; reference product/price/theme differ. |
| Cart | Actual configured item, quantity/remove controls and estimated total exist. Phone dock depends on nonempty cart; wide aside already exists. | State/content differences, not absent components. |
| Checkout/review | Real Pickup/cash Details → Review with direct submission and truthful acceptance notice exists. | Preserve current authority; do not restore the demo delivery/payment/WhatsApp journey. |
| Phone guidance | Persistent format/help and an example placeholder are visible. | Later small copy-only cleanup, preserving normalization, validation and immutable request identity. |
| Search | Actual empty query has initial results; reference has a filled query and different theme. | Focus outline is a candidate for matched-state review, not a proven regression. |
| Call restaurant | No near-top action; existing public phone appears in footer text. | Reuse the public profile phone, with a safe explicit dial action; no private owner-contact exposure. |
| ETA/receipts | No ETA authority or physical receipt result was established by this comparison. | Separate cross-stack ETA contract before code; later display-only receipt phone formatter. |

Merchant names, product names, photos, prices, tax and delivery availability are
real data. Do not alter them to imitate a demo screenshot. The literal `**` in
the current stored restaurant name is not interpreted or stripped automatically.
AR/HE chrome is RTL; EN is LTR; saved menu text remains unchanged in every locale.

## File → public data → Dashboard map

| Concern | Existing files/data authority | First-slice/later boundary |
| --- | --- | --- |
| Public profile | `restaurant_storefront_profiles`; existing manager getter, version/CAS, request ledger/audit | Three nullable content columns; separate narrow manager setter, shared CAS. Generic writer unchanged. |
| Public read | `storefront/src/source/live/{client.ts,decode.ts,adapter.ts}`; authoritative `storefront_menu` | Add `storefront_menu_v2` and strict `decodeHomeContent.ts`; old RPC/decoder unchanged, backend-first deployment. |
| Dashboard | `apps/dashboard/lib/src/storefront/{storefront_models.dart,storefront_profile_repository.dart,storefront_section.dart}` | Authenticated content editor, capability detection, explicit retry/reconciliation and localized preview. |
| Media | Dashboard `storefront_media_slot.dart`, `storefront_media_repository.dart`, `storefront_media_publisher.dart`, `storefront_item_images.dart` | Existing published derivative flow; no fabricated asset or broad republish. |
| Home | `storefront/src/ui/storefront/home/{Home.tsx,HomeChrome.tsx,HomeParts.tsx,MenuParts.tsx,home.module.css}` | Reuse fixed module order/theme; real headline, subline, announcement and safe narrow-header geometry. |
| Public phone | Dashboard `public_phone` → public `restaurant.phone` → adapter `Tenant.phone` | Later Call action uses this same field; no second phone authority. |
| Phone copy | `storefront/src/ui/storefront/checkout/DetailsScreen.tsx`, `storefront/src/i18n/orders.ts` | Later remove persistent guidance/example while retaining useful invalid-only errors and accessibility. |
| Received/status | `LiveReviewScreen.tsx`, `request/{ReceivedScreen.tsx,StatusScreen.tsx}`, `orders/contract.ts` | Later safe Call action and additive accepted estimate; preserve existing rejection reasons/recovery. |
| Cashier phone | `packages/printing/lib/src/receipt/customer_receipt_print_builder.dart`, `apps/pos/lib/src/widgets/receipt_print_preview.dart` | Later one display formatter, coordinated with protected printer work; no spool/transport/ACK changes. |

## Staged completion and truth boundary

1. This PR: real headline/subline/announcement management and versioned public
   mapping, with a narrow header/long-content layout correction.
2. Complete remaining Home content/editor fidelity gaps, then the requested Call
   action on Home and customer received/status using the same public phone.
3. Remove checkout phone guidance in all three locales without changing numbers.
4. Record and independently review the accepted preparation-time contract before
   implementing its atomic decision/SQL/Edge/POS/customer chain. No estimate may
   be inferred from page-load time or the request's expiry.
5. Add display-only local phone formatting and combine compatible POS changes
   into one later signed release when practical. Consumed releases stay immutable.
6. Complete journey and second-restaurant acceptance after the reviewed rollout;
   physical behavior remains owner-verified.

This first slice does not complete Issue #360 or claim production acceptance.
It changes no notification/Cron setting, ordering permission, POS/KDS source,
printing authority, pairing, APK or historical print hold. The v68 transport fix
and the 625 protected holds remain outside its diff. Payment workstreams and
printer PRs #314/#315 retain their separate ownership.
