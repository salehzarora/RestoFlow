# BIZBOT-STOREFRONT-CINEMATIC-001 — mobile design implementation

Owner scope: implement the approved cinematic welcome and mobile menu; reuse the dashboard's background image pipeline and add arbitrary HEX appearance controls. Preserve order/payment behavior and isolate from Claude's ZCredit work.

## Local implementation

- Shared tenant hero photograph behind the welcome, navigation and footer, with a stronger soft overlay behind menu content.
- Mobile typography, open meal rows, larger existing product photography, underlined category tabs and a compact translucent footer. Existing whole-image presentation stays uncropped.
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

Sample settings: primary `#151513`, accent `#e4ad83`; automatic warm text; existing headline formatting with a line break. The proposed welcome photograph is an AI-edited presentation asset based on the original classic burger; it is not the catalog photo and has not been uploaded/published. Restaurant content, media and colors are unchanged on the hosted service. Matching this sample requires selecting that image/palette through the existing dashboard after rollout. Original catalog images retain their photographic backgrounds; truly transparent cutouts require owner-selected prepared images, not CSS removal.

## Bounded validation

- Storefront production build and TypeScript passed.
- Storefront Node suite passed: 437 tests, zero failures; the final button-label token adjustment also passed its four focused appearance tests.
- Isolated local mobile browser: no page errors or horizontal overflow; existing fixture product options open successfully. No order was submitted.
- One read-only review of the SQL/decoder integration found no actionable regression and no file overlap with published payment PRs #370/#371. Unpublished Claude state is unknown; this work uses a separate branch/worktree.
- Flutter/Dart and local PostgreSQL runtimes are unavailable here: dashboard tests and migration pgTAP tests are supplied but remain unexecuted. They must pass in the normal validation environment before hosted rollout.

## Release boundary

This is a local implementation checkpoint. No push, PR, hosted migration, tenant configuration mutation, merge or deployment has been performed. Follow the existing owner-approved branch/PR/automatic Preview workflow, then obtain separate authorization for hosted apply and final merge. Do not deploy the new appearance writer before the updated strict readers.
