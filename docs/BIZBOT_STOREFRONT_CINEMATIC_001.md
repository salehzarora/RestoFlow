# BIZBOT-STOREFRONT-CINEMATIC-001 — mobile design implementation

Owner scope: implement the approved cinematic welcome and mobile menu; reuse the dashboard's background image pipeline and add arbitrary HEX appearance controls. Preserve order/payment behavior and isolate from Claude's ZCredit work.

## Local implementation

- Shared tenant hero photograph behind the welcome, navigation and footer, with a stronger soft overlay behind menu content.
- Refined mobile typography, rounded charcoal meal cards with larger original photography and a dark blend into the product copy, peach filled addition controls, category pills and a soft search field. Existing whole-image presentation stays uncropped.
- One restaurant information panel at the end of the menu, after optional promo/story content, displays the existing service state, pickup/delivery availability, location and hours. The shared public-contact action follows it; brand/tagline and a faint extension of the hero photo complete the footer. No duplicate service panel or header location/status strip.
- Welcome headline/format now reads the existing campaign content in all four locale routes.
- Existing primary/accent controls now drive the background/button palette without replacing a valid owner-selected HEX. Optional text and button-text overrides use the existing content save/version path.
- No new endpoint, cart/payment/order logic, dependency, CSP relaxation, authorization/RLS change or shared localization edit.

The SQL/dashboard extension and deployment sequencing are documented in `BIZBOT_STOREFRONT_CINEMATIC_001B.md`. The prepared migration has NOT been applied.

## Visual evidence

Real browser renders at 390 × 844 of the implemented components, using a temporary local visual fixture with the six observed Maps meal names/prices and original catalog photos. Decorative emoji were omitted only from the local sample. No preview fixture or generated media is shipped in this commit.

- `01-mobile-welcome.png`
- `02-mobile-menu.png`
- `03-mobile-footer.png`
- `04-desktop-welcome.png`

Sample settings: primary `#151513`, accent `#f2ad79`; automatic warm text; existing headline formatting with a line break. The proposed welcome photograph is an AI-edited presentation asset based on the original classic burger; it is not the catalog photo and has not been uploaded/published. Restaurant content, media and colors are unchanged on the hosted service. Matching this sample requires selecting that image/palette through the existing dashboard after rollout. Original catalog images retain their photographic backgrounds; truly transparent cutouts require owner-selected prepared images, not CSS removal.

## Bounded validation

- Storefront production build and TypeScript passed.
- Storefront Node suite passed after the second design refinement: 437 tests, zero failures. Existing source-order guards now pin the service panel inside the footer, retain deletion/duplication negative controls, and verify that disabled services remain visible and labelled unavailable. The public-contact guard follows the consolidated action and its 48px touch target.
- Isolated local mobile browser: no page errors or horizontal overflow; existing fixture product options open successfully. No order was submitted.
- One read-only review of the SQL/decoder integration found no actionable regression and no file overlap with published payment PRs #370/#371. Unpublished Claude state is unknown; this work uses a separate branch/worktree.
- Flutter/Dart and local PostgreSQL runtimes are unavailable here: dashboard tests and migration pgTAP tests are supplied but remain unexecuted. They must pass in the normal validation environment before hosted rollout.

The second refinement changes presentation and its existing layout guards only. It adds no schema, data-source, payment, order, dependency or dashboard change beyond the previous checkpoint. Screenshots were refreshed from the local implementation; these are not hosted-production captures. Historical browser suites that assert earlier design geometry were not run as a broad review cycle.

## Release boundary

This is a local implementation checkpoint. No push, PR, hosted migration, tenant configuration mutation, merge or deployment has been performed. Follow the existing owner-approved branch/PR/automatic Preview workflow, then obtain separate authorization for hosted apply and final merge. Do not deploy the new appearance writer before the updated strict readers.
