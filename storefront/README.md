# BIZBOT Storefront - server-rendered, fixture or live source

STOREFRONT-INFRA-001B established this project as an infrastructure shell,
STOREFRONT-UI-001 turned it into the approved Storefront experience over typed
fixtures, and STOREFRONT-READ-001 gave it a **real read source**: the published
restaurant profile and menu, served by `public.storefront_menu(p_slug)` through
the anonymous (publishable) key, **on the server only**. It writes nothing:
ordering, payment, WhatsApp and status are not connected (live mode is
browse-only). The hosted apply of its migration, the provider settings and any
deployment are separately approved steps; nothing in this directory performs
them.

What it is:

- A Next.js App Router project built as a **server build** (`next build`, no
  `output: 'export'`). Tenant routes are dynamic and ISR-cached per URL:
  `revalidate = 60` and `expireTime = 360` (served
  `Cache-Control: s-maxage=60, stale-while-revalidate=300`).
- Four locale roots - `/` (Arabic), `/ar`, `/en`, `/he` - each emitting the
  correct `<html lang>` and `<html dir>` in the served HTML, before hydration.
  Crossing between them is a full document load: they are separate root
  layouts, and that is the accepted choice.
- One read seam, `src/source/storefront.ts`, with two sources selected by the
  **server-only** env `STOREFRONT_SOURCE`:
  - `fixture` (default): the UI-001 fixture tenant `maps-burger`, no network;
    the `/r/:ref` received / status document and the fixture gateway exist.
  - `live`: `src/source/live/` calls the RPC with global `fetch` from server
    code only (`STOREFRONT_SUPABASE_URL`, `STOREFRONT_SUPABASE_ANON_KEY`,
    read inside functions at request time; see `.env.example`), decodes the
    exact envelope key set (`decode.ts`, fail-closed), maps it to the UI
    model (`adapter.ts`), and serves any published slug. `not_found` renders
    the Unknown document (404); a transport failure or the 5 s timeout throws
    (ISR keeps the last good document; never the fixture). `/r/*` is a 404,
    `/checkout`, `/payment` and `/review` bounce to `/cart`, and the send CTA
    never exists (`service.ordering_enabled` is the literal `false`).
  - A live deployment must be **built** with `STOREFRONT_SOURCE=live`: in
    fixture mode `generateStaticParams` prerenders the fixture slug and the
    demo request ref at build time.
- The eleven approved screens: intro, home, search, product sheet, cart,
  checkout, payment, review, received, status, unknown. Routes: `/s/:slug`,
  `/s/:slug/{menu,search,cart,checkout,payment,review}` and (fixture mode only)
  `/r/:ref`.
- A per-slug, per-`menu_version` cart in `localStorage` (`sf:v1:cart:<slug>`)
  and two session flags; everything typed at checkout lives in application
  memory only.
- Money in integer minor units and tax in basis points from one quote
  authority (`src/money/quote.ts`); a self-hosted Rubik in three script
  subsets (`src/fonts/README.md`); a per-tenant theme derived on the server
  from the served brand colours and applied through the CSSOM under
  `style-src 'self'`; tenant text rendered as React text (a hostile display
  name is data, never markup); category icons from a registry only
  (`src/source/live/icons.ts`), never from tenant data.
- Ordering that is exactly `open` **and** enabled: a closed, paused or
  browse-only restaurant refuses every step and the send in place, states why,
  and keeps the cart and the typed draft
  (`src/ui/storefront/checkout/eligibility.ts`).

What it deliberately is not:

- No BFF, server action, request-time API of its own, middleware or proxy: the
  server component reads the database directly over the same-origin server
  boundary; the browser never talks to the database (`connect-src 'self'`).
- No Supabase client library, no credential in any document or client chunk
  (`tests/output/output.test.mjs` scans every emitted chunk for the env
  names, `apikey`, `/rest/v1/` and JWT shapes), no service-role key anywhere.
- No real order, payment or message: live mode is browse-only; fixture mode
  keeps the simulated gateway and says so on every received / status screen.
- No customer-field persistence of any kind: names, phones and addresses are
  never stored, logged, sent, copied or serialised into a document.

Every document is byte-identical for every visitor of the same URL, so no
document carries a cart, a draft, a request or a price that belongs to someone.
Images are immutable public derivatives (`storefront-media` bucket) on exactly
one extra `img-src` origin (`vercel.json`).

## Commands

```
npm run typecheck                          tsc --noEmit
npm test                                   node --test tests/*.test.mjs
npm run build                              the server build (fixture source; SF_EVIDENCE_ROUTES unset)
SF_EVIDENCE_ROUTES=1 npm run build         the local EVIDENCE build (adds the demo-* scenario slugs)
STOREFRONT_SOURCE=live npm run build       a LIVE build (no tenant or request route prerendered)
npm run start                              next start (serves .next; PORT / -p)
node scripts/snapshot-server.mjs           real `next start` -> fetch every route into out/ (+ SNAPSHOT.json)
node --test tests/output/output.test.mjs   assertions over the snapshot in out/
node scripts/audit-output.mjs              budgets, file types, off-origin references
node scripts/audit-inputs.mjs              build-input hygiene
node scripts/measure-firstload.mjs         per-route first-load JS, CSS and font preloads against the written limits
node scripts/isolated-build.mjs            rebuild in a scratch copy and compare the client output
node scripts/filter-proof.mjs              three-project deployment-filter proof in isolated git fixtures
node scripts/serve-out.mjs                 loopback static server for out/ (PORT=...)
npx playwright test -c tests/browser/playwright.config.ts <spec>          Chromium
npx playwright test -c tests/browser/playwright.cross.config.ts           Firefox + WebKit smoke
```

### Local live evidence (Docker Supabase only)

```
node scripts/seed-local.mjs                apply scripts/local-storefront-seed.sql to the LOCAL database
                                           (STOREFRONT_LOCAL_DB_URL, loopback only; refuses any other host)
node scripts/local-api-shim.mjs            loopback /rest/v1/* -> local PostgREST (when kong is not running)
STOREFRONT_LOCAL_API_URL=http://127.0.0.1:4700 STOREFRONT_LOCAL_ANON_KEY=<local anon key> \
  npx playwright test -c tests/browser/playwright.config.ts tests/browser/storefront-read-001.spec.ts
```

The READ-001 spec always runs its STUB block (an in-process envelope server)
and runs its REAL block only when those two variables are set; it refuses a
fixture build (a live build is required in `.next`). Every `next start` on one
`.next` directory shares its on-disk ISR cache, so the spec uses disjoint slugs
per block and purges the cached tenant documents before each server starts.
The seed goes through the Supabase CLI, which connects without TLS only to the
database port named in `supabase/config.toml`; on a stack that runs on other
ports, use that port in `STOREFRONT_LOCAL_DB_URL` (or shift `config.toml`
locally for the run and revert it before committing).

Demo scenarios are selected with `?fx=<token>` and are read only inside the
fixture source (`src/source/fixtures.ts`); the live source ignores the switch.

`storefront/scripts/` and `storefront/tests/` are support code. The deployment
filter never scans them, which is why they may use Node built-ins while the
application source may not (server-only modules under `src/source/live/` and
`src/source/storefront.ts` may read `process.env`; nothing else may). The
decision records for UI-001 are under `docs/UI-001/`, the READ-001
implementation record is `docs/READ-001/IMPLEMENTATION.md`, and the
owner-approved, scoped acceptance exceptions the output validators apply
(CSS-UI001-01, PERF-UI001-01) are the frozen table in
`scripts/acceptance-exceptions.mjs`, recorded in
`docs/UI-001/PHASE_EF_COMPLETION.md` §7.
