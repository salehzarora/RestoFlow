# BIZBOT Storefront - static export, fixture-driven

STOREFRONT-INFRA-001B established this project as an infrastructure shell;
STOREFRONT-UI-001 turned it into the approved Storefront experience, running
entirely on typed fixtures and local state. It is **not yet connected to a
backend**, it is **not deployed**, and nothing in it writes production data.

What it is:

- A Next.js App Router project built with `output: 'export'` to static
  HTML/CSS/JS in `out/`.
- Four locale roots - `/` (Arabic), `/ar`, `/en`, `/he` - each emitting the
  correct `<html lang>` and `<html dir>` in the served HTML, before hydration.
  Crossing between them is a full document load: they are separate root
  layouts, and that is the accepted choice.
- The eleven approved screens for one fixture tenant (`maps-burger`): intro,
  home, search, product sheet, cart, checkout, payment, review, received,
  status, unknown. Routes: `/s/:slug`, `/s/:slug/{menu,search,cart,checkout,
  payment,review}` and `/r/:ref` (received and status are two post-hydration
  states of the one request document; exactly one opaque demo ref ships).
- A per-slug cart in `localStorage` (`sf:v1:cart:<slug>`) and two session
  flags; everything typed at checkout lives in application memory only.
- Money in integer minor units from one quote authority
  (`src/money/quote.ts`); a self-hosted Rubik in three script subsets, two
  of them preloaded per locale root and the third fetched on demand
  (`src/fonts/README.md`); a per-tenant theme derived at build time and
  applied through the CSSOM under `style-src 'self'`.
- Ordering that is exactly `open`: a closed or paused restaurant refuses every
  step and the send in place, states why, and keeps the cart and the typed
  draft (`src/ui/storefront/checkout/eligibility.ts`).

What it deliberately is not:

- No BFF, server action, request-time API, middleware or proxy.
- No Supabase client, credential, environment variable or real menu data.
- No real order, payment or message: the send goes to a fixture gateway, the
  status comes from a fixture source, WhatsApp is simulated (never opened,
  never "sent") and every received / status screen says so.
- No customer-field persistence of any kind: names, phones and addresses are
  never stored, logged, sent, copied or serialised into a document.

Every static document is byte-identical for every visitor, so no document
carries a cart, a draft, a request or a price that belongs to someone.

## Commands

```
npm run typecheck                          tsc --noEmit
npm test                                   node --test tests/*.test.mjs
npm run build                              the SHIPPED export (SF_EVIDENCE_ROUTES unset)
SF_EVIDENCE_ROUTES=1 npm run build         the local EVIDENCE export (adds demo-* scenario slugs)
node --test tests/output/output.test.mjs   assertions over the built out/ tree
node scripts/audit-output.mjs              budgets, file types, off-origin references
node scripts/audit-inputs.mjs              build-input hygiene
node scripts/measure-firstload.mjs         per-route first-load JS, CSS and font preloads against the written limits
node scripts/isolated-build.mjs            rebuild in a scratch copy and compare
node scripts/serve-out.mjs                 loopback static server for out/ (PORT=...)
npx playwright test -c tests/browser/playwright.config.ts <spec>          Chromium
npx playwright test -c tests/browser/playwright.cross.config.ts           Firefox + WebKit smoke
```

Demo scenarios are selected with `?fx=<token>` and are read only inside the
fixture layer (`src/source/`); a live adapter replaces that folder and the
switch disappears with it.

`storefront/scripts/` and `storefront/tests/` are support code. The deployment
filter never scans them, which is why they may use Node built-ins while the
application source may not. The decision records for UI-001 are under
`docs/UI-001/`.
