# STOREFRONT-READ-001 — implementation record (local only)

Work ID `STOREFRONT-READ-001`. Branch `feat/STOREFRONT-READ-001-live-menu-read`
(cut from `5c56dd67`, the open HOST-FIX-001 head, so that the Next output
contract of PR #286 is included; owner plan decision D12 merges #286 first).
Sealed plan: `worktrees/output/storefront-read-001-plan-20260923T152536Z/`
(outside git). Owner decisions taken with the implementation authorization on
2026-09-23: **D0** (the read-slice security work executes inside this
implementation under independent review), **D1** (ratify DECISION D-037 with
one narrow amendment: only the explicitly enumerated Storefront public
functions may be `SECURITY DEFINER`; no general exception), **D2** (static
export → server-rendered, revalidated live read), **D13** (every future
Storefront build is a server build; the protected fixture deployment
`dpl_4bCrhnW4in27xQYtTcekx63xcBea` stays immutable evidence). The remaining
plan decisions are taken at their recommended defaults (D3 bucket, D4 slug on
the profile row, D5 string family, D6 60 s / 300 s, D7 / D7b ILS + exclusive
tax, D8 env names, D10 multi-select, D11 fallbacks).

**Boundary honoured:** no push, no PR, no merge, no deploy, no provider build,
no provider setting change, no hosted migration. `resto-flow` builds = 0,
`bizbot-site` builds = 0, `bizbot-storefront` builds = 0. The decision record
is `docs/DECISIONS.md` **D-039** (PROPOSED); the contract is
`docs/API_CONTRACT.md` §4.42; the entities are `docs/DOMAIN_MODEL.md`
§4.7–§4.8; the proofs are T-016 (amended) and the new T-017 in
`docs/SECURITY_AND_THREAT_MODEL.md` §14; the hosted procedure is
`docs/DEPLOYMENT.md` §16.

## 1. What was built

### 1.1 Database slice — `supabase/migrations/20260923120000_storefront_read_001.sql`

| Object | Role |
|---|---|
| `app.storefront_opening_hours_is_valid(jsonb)` | IMMUTABLE validator of `{"weekly":[…],"exceptions":[…]}` (CHECK + writer) |
| `app.storefront_service_window(jsonb, text, timestamptz)` | today's window only (the current one when open, else the next one starting today; null otherwise), `open_now`, `next_open` within 7 days (yesterday..+7 days scan, midnight wrap) |
| `app.storefront_media_prefix(uuid)` | opaque 32-hex per-restaurant prefix (`sha256('storefront-media:' ‖ id)`) |
| `public.storefront_media` | published WebP derivative map; key shape `^[0-9a-f]{32}/[0-9a-f]{64}\.webp$` enforced against prefix + content hash; RLS forced, deny policies, no grants |
| `public.restaurant_storefront_profiles` | 1:1 profile: slug (storage grammar, reserved words, partial-unique live), brand, hours, pause, publish state, `version`; CHECK `browse_only` forces `ordering_enabled = delivery_enabled = false`; RLS forced, deny policies, no grants |
| bucket `storefront-media` | public, 512 KiB, `image/webp`; SELECT / INSERT / UPDATE / DELETE `to authenticated` gated by `app.can_write_storefront_object(name)` → `app.can_write_storefront_media(org, restaurant)` (rank ≥ 2) through a registered key only |
| `app.storefront_publish_blockers(...)` | ordered blockers `slug_missing, branch_missing, timezone_missing, currency_not_ils, tax_not_exclusive, no_live_item, hours_missing` |
| `app.set_restaurant_storefront_profile(...)` + public INVOKER wrapper | the only writer: allowlisted patch keys, rank ≥ 2 with `settings.storefront.update_denied` audit, `FOR UPDATE` locks, `management_idem_*` idempotency, CAS `version_conflict`, typed `invalid` reasons, `settings.storefront.updated` audit; `authenticated`-only |
| `app.get_restaurant_storefront_profile(...)` + wrapper | manager+ prefill / preview (profile, derived tz / currency / tax, blockers, `media_prefix`); `authenticated`-only |
| `public.storefront_menu(p_slug text)` | **the** anon-only read: `STABLE`, `SECURITY DEFINER`, owner `postgres`, `set search_path = ''`; grants `revoke all from public, anon, authenticated; grant execute to anon`; slug-only scope, no membership helper; uniform `not_found`; typed `payload_limit` (100 / 500 / 2,000 / 8,000); exact served-key set; `menu_version = '<profile.version>.<epoch>'`; relative public media paths |
| final `DO` assertion | anon EXECUTE set in `public` = `{storefront_menu(text)}`; `authenticated` revoked from it; `SECURITY DEFINER` set in `public` = the same; `anon` has no `app` USAGE |

Applied to the **local** Docker database only (`supabase migration up --local`,
141 migrations, head `20260923120000`). Not applied to hosted.

### 1.2 Storefront — live read path

- `src/source/types.ts` — `StorefrontSource.getStorefront(slug): Promise<StorefrontResolution | null>` (async), `StorefrontResolution { view, preset, groups, zones, taxRateBp, menuVersion }`, `BasisPoints`, `TenantService.orderingEnabled`, `Tenant.heroImage: string | null`, `FixtureTenantSource`.
- `src/source/storefront.ts` — `sourceMode(env)` (`fixture` | `live`, server-only env), `fixtureStorefrontSource` (demo scenario slugs only under `SF_EVIDENCE_ROUTES=1`), `storefrontSource`, `getStorefront`, `storefrontSlugs` (fixture slug in fixture mode; `[]` in live mode).
- `src/source/live/client.ts` — `liveConfig(env)`, `storefrontMenuRequest(config, slug)` (exact PostgREST shape: `POST …/rest/v1/rpc/storefront_menu`, `apikey` + `Authorization: Bearer`, JSON body `{p_slug}`), `fetchStorefrontMenu(slug, config?)` with a `typeof window` guard and `AbortSignal.timeout(5000)`.
- `src/source/live/decode.ts` — strict exact-key decoder of the envelope (`EnvelopeError`, `CAPS`); an extra or missing key fails closed.
- `src/source/live/adapter.ts` — `mediaUrl` (relative storage path → absolute on `STOREFRONT_SUPABASE_URL`), `adaptStorefront(envelope, origin)` (envelope → `StorefrontResolution`), `liveStorefrontSource(config?)`: `not_found` → `null`; any other failure, transport error, timeout or slug mismatch → throw.
- `src/source/live/icons.ts` — the category icon registry (49 keys → 24-grid paths, `DEFAULT_ICON_KEY = 'menu'`); an unknown `icon_key` falls back, tenant data never becomes an SVG path.
- `src/source/lookup.ts` — `groupsFor(groupIds, groups)`, `zoneFor(id, zones)` replace the fixture-bound lookups.
- Routes: all 28 `app/**/s/[slug]/**/page.tsx` regenerated — `dynamicParams = true`, `revalidate = 60`, `generateStaticParams` from `storefrontSlugs()`; `not_found` → `notFound()`. `/r/[ref]` stays fixture-only (`requestRefs()` → `[]` in live mode).
- `next.config.mjs` — `output: 'export'` removed; `expireTime: 360`; `images.unoptimized`, `reactStrictMode`, `poweredByHeader: false`, `trailingSlash: false` kept.
- Data flow: `CartRuntime.tsx` (`MenuData`, `MenuContext`, `useMenuData`, `CartScope({cart, menu})`), `FlowRuntime.tsx` (items / groups / zones / taxRateBp / menuVersion props; bounce to `/cart` when ordering is off; `activeGateway = null` when off), `StorefrontRuntime.tsx`, `Home.tsx`, `Search.tsx`, `DetailsScreen.tsx` (`zones` prop), `ReviewScreen.tsx` (`gateway: RequestGateway | null`), `CartScreen.tsx` (`orderingEnabled`, banner `ordering-off`), `HomeParts.tsx` (`OrderingOffNotice`, conditional hero / subline), `Intro.tsx`, `RequestRuntime.tsx`.
- Money: `money/quote.ts` takes `groups` + `taxRateBp` (tax = `round((subtotal + fee) × rate_bp / 10000)`), `money/format.ts` `formatRateBp`; `cart/cartModel.ts` `resolveLine(line, items, allGroups)` / `summarise(state, items, groups)`; `cart/useCart.ts` takes the groups.
- Eligibility: `checkout/eligibility.ts` — `'ordering-off'` is the **first** blocker; `orderingBlocker(state, orderingEnabled)`; `submitEligibility({ orderingEnabled, … })`; `orderingReason` maps to `orderingOfflineTitle`.
- i18n: `orderingOfflineTitle` / `orderingOfflineBody` × ar / he / en; tax label templates `{p}%`.
- `vercel.json` — CSP `img-src 'self' data: https://oqmevrndtivqxgyvcmwy.supabase.co` (exactly one extra origin; `connect-src 'self'` unchanged).
- `.env.example` — `STOREFRONT_SOURCE`, `STOREFRONT_SUPABASE_URL`, `STOREFRONT_SUPABASE_ANON_KEY` (server-only; documented).

### 1.3 Shared engine, CI, lanes

- `tools/vercel/ignore-build.mjs` — `STOREFRONT_CONFIG_HASH` re-pinned to `59bff99cca265f1246073aec3da7dbbff69a3699bdadaf9587e9baf1d7b01705` (was `4aa433d2…`); `tools/vercel/ignore-build.test.mjs` fixture + mutation case follow. **Fan-out:** a shared-engine change builds all three provider projects **once per environment event** — three Preview builds on the first push and three Production builds at the merge (§7; T-S12, recorded in the evidence packs before any push).
- `.github/workflows/ci.yml` — the storefront lane runs the server build, then `scripts/snapshot-server.mjs` (real `next start` → `out/`), then the output / audit / first-load lanes over the snapshot.
- `scripts/snapshot-server.mjs` — starts `next start` on a loopback port, fetches every route into `out/` (documents, one RSC flight `.txt` per document via the `?_rsc=` redirect, `_next/static`, `public/`, `404.html`, `SNAPSHOT.json`).
- `scripts/budgets.mjs` — `MEDIA_ORIGIN`, `MEDIA_PATH_PREFIX`, `documentBytesProposal: 200000` (a server-rendered document carries its RSC payload); `serverFunctions` removed. `scripts/audit-output.mjs` allows the media origin for `<img>` only. `scripts/isolated-build.mjs` compares `.next/static` + the `BUILD_ID` marker.
- Local live evidence: `scripts/local-storefront-seed.sql` (one `DO` block; synthetic tenants `sf-synth-a` open / hostile name / derivative / sold-out, `sf-synth-b` paused / light / grid / tax off, `sf-synth-c` unpublished; UUID prefix `00000000-0000-0000-0000-00ad1…`), `scripts/seed-local.mjs` (loopback-only, refuses any other host), `scripts/local-api-shim.mjs` (loopback `/rest/v1/*` → local PostgREST when kong is not running).

## 2. Tests and results (local, 2026-09-23)

| Lane | Command | Result |
|---|---|---|
| pgTAP T-016 (amended) | `supabase test db --local supabase/tests/public_surface_acl_remediation_001_test.sql` | **62 / 62** — A1 / A5 / D1 by set equality against `sec001_allowlist = {storefront_menu(text)}`; E6b proves the SEC-001 schema-wide revoke would strip the allowlist |
| pgTAP T-017 (new) | `supabase test db --local supabase/tests/storefront_read_001_test.sql` | **98 / 98** — A introspection (18, incl. hosted-shape re-stamp, real `authenticated` 42501, helper grants), B bucket / policies (8), C projection as real `anon` (24), D uniform `not_found` + closed / paused + `payload_limit` (15), E write RPC / CHECKs / read (28, incl. `slug_immutable`), F (2), G hours helper at fixed instants (3) |
| storefront unit suites | `node --test tests/*.test.mjs` (Node 24) | **283 / 283** (incl. new `tests/sf-live.test.mjs`, 19) |
| type check | `npm run typecheck` | clean |
| shared engine | `node --test tools/vercel/ignore-build.test.mjs` | **159 pass, 0 fail, 2 skipped** (161) |
| filter proof | `node scripts/filter-proof.mjs` | **PASSED** — A / B / C / D1–D4 decided as required |
| isolated build | `node scripts/isolated-build.mjs` | PASSED, 33 vs 33 client files, 0 differing |
| fixture snapshot lanes | `npm run build` → `snapshot-server.mjs` → `tests/output/output.test.mjs` (28) → `audit-output.mjs` → `measure-firstload.mjs` → `audit-inputs.mjs` | green on the final tree; 37 documents, client static 982,006 B, server bundle 13,065,444 B, largest document `/s/maps-burger/menu` 130,256 B (proposal 200,000); the two owner-approved UI-001 exceptions (CSS-UI001-01, PERF-UI001-01) still apply |
| live build | `STOREFRONT_SOURCE=live npm run build` | prerendered `/`, `/ar`, `/en`, `/he`, `/_not-found`, `/_global-error` only; 32 dynamic routes |
| served header | `next start` + fetch | `Cache-Control: s-maxage=60, stale-while-revalidate=300` on tenant documents; no `Set-Cookie` |
| Playwright READ-001 | `tests/browser/storefront-read-001.spec.ts` (STUB block always; REAL block through the shim against the seeded local database) | **8 / 8** on the 2026-09-23 sealed-pack build (**10 / 10** after the correction pass added the hours and fixture-token rows; see §9 and the correction pack) — RPC called with the anon key over the exact PostgREST shape and never by the browser; the configured key value and every credential shape absent from every rendered document; two tenants × four roots, no fixture leakage, hostile text as text, browse-only, at least one published derivative rendered, the serialised tax rate per tenant; checkout routes bounce, `/r/*` 404; per-URL cache with the 60 s header; `not_found` → 404 document, error / timeout → error page, never the fixture; a change on a never-touched slug is visible after the revalidate window with exactly one render inside it; REAL: the seeded tenants served by `public.storefront_menu`, tax rate `1800` / `0` per tenant, unpublished and unknown slugs are the same 404 |

Secrets: the local anon key is read from `supabase status -o env` into the
process environment only and is masked in every saved log (`<ANON_KEY>`); no
log in the evidence pack contains a JWT.

## 3. Fixture / live separation

| | fixture (`STOREFRONT_SOURCE` unset / `fixture`) | live |
|---|---|---|
| tenant | `maps-burger` (+ `demo-*` under `SF_EVIDENCE_ROUTES=1`) | any published slug |
| `generateStaticParams` | the fixture slug (prerendered) | `[]` (nothing prerendered; every slug resolved at request time) |
| `/r/:ref` | one opaque demo ref (prerendered) | 404 |
| ordering | fixture gateway, simulated WhatsApp | **off** — `service.ordering_enabled = false`; `send` never exists; `/checkout`, `/payment`, `/review` → `/cart` |
| `?fx=` scenarios | read by the fixture source | ignored |
| network | none | server → `STOREFRONT_SUPABASE_URL` only; browser → same origin only |
| failure | n/a | `not_found` → 404 document; else throw (last good document or framework error page) — never the fixture |

A live deployment must be **built** with `STOREFRONT_SOURCE=live`; the
Playwright spec refuses a fixture build through `.next/prerender-manifest.json`.

## 4. Findings worth keeping

- **Every `next start` on one `.next` directory shares its on-disk ISR cache**
  (`.next/server/app/<root>/s/<slug>/*.html|.rsc|.meta`). The first Playwright
  run served the STUB block's rendered documents to the REAL block's server
  (stale-while-revalidate hid the switch of source). The spec now uses disjoint
  slugs per block (`sf-stub-*` vs the seeded `sf-synth-*`) and purges the cached
  tenant / request entries before each server starts. On the provider the ISR
  cache is per deployment, so this is a local-evidence trap, not a hosted one.
- The menu document of an **empty** cart carries no tax row (it renders on the
  cart aside once a line exists); the served rate is asserted through the
  serialised `taxRateBp` instead.
- `next start` answers a `RSC: 1` request with a 307 to `?_rsc=…`; the snapshot
  follows that single hop to capture the flight payload.
- `supabase db query -f` runs the file as **one** prepared statement, so the
  seed is a single `DO` block and the self-check is a separate query.
- `supabase migration up --local` needs the CLI's configured port; on this
  machine the database listens on 55322 (WinNAT exclusions), so the local
  `config.toml` was shifted temporarily and **reverted before commit**.
- The CLI (v2.107.0) connects **without TLS only** to the database port named
  in `supabase/config.toml` ("Connecting to local database…"); any other
  loopback port is treated as remote, TLS is forced and `sslmode=disable` is
  ignored (except, oddly, under `--debug`). `scripts/seed-local.mjs` documents
  this and prints a hint on the TLS error; on this machine the seed was applied
  with the config shifted (and once through `psql` in the container).
- After a migration edit, the local database was torn down to the pre-READ-001
  state (a scratchpad SQL that drops only the objects this migration created
  and its `schema_migrations` row; no `db reset`) and the **final file was
  applied from scratch** by `supabase migration up --local` before the final
  pgTAP runs, so the suites prove the committed file, not an accumulated state.

## 5. Not done here (each its own Work ID / approval)

`web_order_requests`, real checkout submission, payment, WhatsApp, POS inbox,
delivery backend, analytics, Dashboard profile editor + media publish action,
hosted drift watch + migration apply (`docs/DEPLOYMENT.md` §16), provider env /
Deployment Protection / plan check, on-demand invalidation, slug history,
per-locale tenant content (Q-025..Q-030).

## 6. Hosted posture

Read-only drift-watch queries are **prepared** in `docs/DEPLOYMENT.md` §16
(queries 1–14). They were **not run**: this machine holds no already-supported
read-only hosted access without changing credentials or settings, and the
packet authorises no hosted mutation. Nothing was applied, deployed, built or
changed on any provider.

## 7. Publication fan-out record (T-S12, measured before any push)

`tools/vercel/ignore-build.mjs` run in a disposable clone of the branch
(`C:/tmp/sf-fanout-read001`, deleted afterwards) with
`VERCEL_GIT_PREVIOUS_SHA = f93473bf…` (current `main`) and
`VERCEL_GIT_COMMIT_SHA` = the local head at the time of the record (run twice:
on the first head reviewed, and again on the final regrouped head — same
result both times; the exact shas are in the evidence pack `fanout-t-s12.log`),
each selector in its project directory:

| selector | decision | reason | categories |
|---|---|---|---|
| `product` (root) | BUILD | `relevant_changes` | `shared_engine: 1`, `storefront_runtime: 67`, `storefront_local: 23`, `tests_docs: 13` |
| `marketing` (`site/`) | BUILD | `relevant_changes` | same |
| `storefront` (`storefront/`) | BUILD | `unsupported_build_contract` | — (fail-safe) |

The product and marketing builds are the shared-engine fan-out (the
`STOREFRONT_CONFIG_HASH` pin changed). The storefront decision is also a
BUILD, but by **fail-safe**: `inspectStorefront` validates the contract at
the baseline **and** the head, and the baseline (`main`) still carries the
pre-READ-001 `next.config.mjs` (old hash) and output contract, so the guard
fails at the baseline. Once a deployment carrying the new contract is the
previous successful deployment of an environment, the storefront selector
classifies normally again there (`scripts/filter-proof.mjs` D1–D4 prove
`relevant_changes` / `unaffected_changes` when both trees carry the new
contract). **Count, per environment event (corrected after independent
review):** every environment evaluates against its OWN previous successful
deployment, so this change triggers **three builds per event** — three Preview
builds on the first push and three Production builds at the merge (six for
READ-001 alone; three more if PR #286 is merged on its own first); further
pushes to the branch classify per project (product / marketing IGNORE unless
the engine changes again, storefront BUILD). Never "3 builds" without that
qualifier. No push was made; this is a record, not an action.

## 8. Independent adversarial review (local, 2026-09-23) and what changed

A four-lens review (security / ACL, RPC + client correctness, test non-vacuity,
docs + packet compliance) with one adversarial refuter per finding was run on
the first local head `ec94d424` (10 agents, 25 raw findings, 6 confirmed, 0
refuted, 19 reported without a refutation pass). Every confirmed finding and
every unverified finding that a re-read of the code confirmed was folded in
before the final commits (the history was regrouped so that each commit is
self-consistent; the review head is recorded in the evidence pack together
with the exact diff that closed it):

| # | Finding (severity) | Resolution |
|---|---|---|
| 1 | Docs said the slug is immutable; the writer renamed it freely (high → medium) | `app.set_restaurant_storefront_profile` refuses a different slug on a live row with `slug_immutable`; T-017 E13b proves it; API §4.42.2 / Q-029 updated |
| 2 | `storefront-media` UPDATE / DELETE policies unreachable without a SELECT policy (medium) | narrow `storefront_media_select` policy with the same registered-key gate; T-017 B4–B6 pin four policies; API §4.42.4 / DOMAIN_MODEL §4.8 / T-017 text updated |
| 3 | Closed state served the NEXT window (up to 7 days out) as `opens` / `closes`; the adapter dropped `next_open` (medium) | `app.storefront_service_window` serves `opens` / `closes` for today only (null otherwise) and `next_open` as the forward pointer; `TenantHours.nextOpen` carried through the adapter; T-017 F2 / G3 and API §4.42.1 aligned |
| 4 | Text caps counted in code points on the server but UTF-16 units in the decoder (medium) | the decoder counts code points; a unit test decodes a 600-code-point description ending in an emoji |
| 5 | No lane asserted the key VALUE / credential shapes are absent from a live document (medium → low) | both Playwright blocks assert the configured key literal and the `sb_publishable_` / JWT shapes are absent from every rendered document; a unit test asserts the serialised resolution never carries the key or `/rest/v1` |
| 6 | CI never built the storefront in live mode (medium → low) | CI step: `STOREFRONT_SOURCE=live npm run build` + a manifest assertion that no tenant / request route is prerendered (network-free) |
| 7 | `next.config.mjs` landed in the db commit while its hash pin landed in the storefront commit (unverified, confirmed) | commits regrouped: config + pin + engine fixture travel together |
| 8 | API §4.42.3 put `publish_ready` / `publish_blockers` / `media_prefix` at the top level (they are under `derived`); §4.42.2 said "no membership" yields the typed envelope (it raises `42501`); reason list missed `logo_media_id_invalid` / `hero_media_id_invalid`; `publish_precondition` wording; "close ≤ open" vs the validator refusing `open = close`; §5 cross-references stale (unverified, confirmed) | all corrected in API_CONTRACT / DOMAIN_MODEL |
| 9 | `app.storefront_publish_blockers` and the other caller-blind DEFINER helpers were ungranted but not explicitly revoked from `authenticated`; the A6 `prosrc` guard missed `current_setting` / `current_organization_id` (low) | explicit revokes for the four helpers; T-017 A6 regex widened, A6b pins the helper grants |
| 10 | Tags were vocabulary-filtered but not de-duplicated (a duplicate-heavy array could exceed the decoder cap) (low) | `jsonb_agg(distinct t)` |
| 11 | Vacuous `\|\| true` negative control in the credential scan; `not.toContain('{p}')` trivially true; media-origin loop vacuous on zero images; freshness test reused a warmed URL (low) | real negative control; serialised-rate assertion per tenant; `expectImages ≥ 1`; dedicated `sf-stub-fresh` slug with a one-render assertion |
| 12 | Slug availability oracle for managers via `slug_taken` (low) | recorded under Q-029 and in API §4.42.2 (inherent to a global namespace; not changed) |
| 13 | Overlapping same-day windows report the earliest window's close (low) | documented as a constraint of the hours model (API §4.42.1, migration comment); not changed |

Unchanged by the review: the anon-only grant posture, the uniform `not_found`,
the served-key sets, the browse-only live mode, the fixture / live separation.

## 9. Independent review verdict (2026-09-23) and the local correction pass (2026-09-24)

The independent read-only review of `642b5aae` (pack
`worktrees/output/storefront-read-001-review-20260923T183213Z/`) returned
**CHANGES REQUIRED**: one BLOCKER (a provider build without `STOREFRONT_SOURCE`
silently served the fixture demo), one MAJOR (closed-with-no-window-today
rendered dangling hours text; `next_open` was never rendered) and bounded
pre-hosted-PRE items. The owner-approved correction pass closed them locally,
without redesigning READ-001:

| # | Finding | Correction |
|---|---|---|
| A (BLOCKER) | absent / empty `STOREFRONT_SOURCE` → fixture in any context | `src/source/mode.ts`: explicit `fixture` / `live` everywhere; absent / empty → fixture **only outside a provider context**; in a Vercel build or runtime (`VERCEL` / `VERCEL_ENV`) absent, empty, whitespace-only or misspelled **throws** (build and request); `request-fixture.ts` applies the same rule; unit matrix (7 negative controls incl. provider explicit fixture / live and the non-provider default); CI: a provider-shaped live build must pass and a provider-shaped build without the variable must fail with the misconfiguration error; README / `.env.example` / D-039 state the rule and the HOST-001 demo provider prerequisite |
| B (MAJOR) | dangling `opens ` / `Opens at .` / `Hours –` | one renderer `src/ui/storefront/home/hoursCopy.ts` from the live model; `TenantHours.nextOpenAt` (weekday + time on the restaurant's clock, computed on the server by `nextOpenParts`) and `timezone`; new dictionary keys (`opensOn`, `closedNow`, `closedBodyOn`, `closedBodyNoHours`, `weekday0..6`) × ar / en / he; paused never invents a next-open; unit matrix (7 states × 3 locales) + browser rows (closed-next, closed-none, overnight, paused × 4 roots) |
| C1 | procedure-blind guards | `prokind in ('f','p')` in the migration's final DO block and every T-016 set guard; T-017 A6c–A6e create an anon-executable SECURITY DEFINER procedure inside the transaction, prove the widened guard reports it, drop it, and prove the set is the allowlist again |
| C2 | decoder `min/max_select` cap 1000 | decoder accepts the storage domain (`0..2147483647`); the adapter judges the relation (single ignores max; an unsatisfiable multi group is dropped, bounded); boundary + malformed tests incl. `1001`, `5000`, int4 max, min > max |
| C3 | permissive `paused_until` | one wire format (RFC 3339 with explicit `Z` / offset, or null) validated before the cast; T-017 E28–E33 (`tomorrow`, offset-less, `infinity`, bare date refused; `+03:00` stored as the instant; null clears); API §4.42.2 documents it |
| C4 | storage policies asserted structurally only | T-017 B9–B22 as real principals: anon lists / uploads / updates / deletes nothing; an Org A owner sees, moves (to another registered key) and retracts only its own registered derivative, cannot use an unregistered key or another tenant's key; Org B's owner sees only Org B's; a cashier sees nothing and cannot upload; the SELECT policy enables no anonymous enumeration |
| C5 | `?fx=` tokens on a live cart | `StorefrontResolution.source` (`fixture` / `live`) threaded to the runtimes; the flow and the aside read a token only for `fixture`; browser negative control over every token family on a live tenant; the fixture control (UI-001 D-G19–G21) still passes |
| D1 | weakened aside money guard | `asideMoneyOffences()` (regex shapes, whitespace-insensitive; only `formatRateBp(quote.taxRateBp)` and the `=== 0` check allowed) + negative control |
| D2 | server-only import guard by literal prefix | `serverOnlyImports()` by path shape (alias or any relative path) + negative control |
| D3 / D4 / D5 | stale static-export prose; contradictory D-037 status; "3 builds" | engine comments, DEPLOYMENT §15 and the contract test reworded for the server build; D-037 status single-valued (owner-approved, ratified with the amendment); D-039 and §7 count builds per environment event |
| D6 | evidence currency | forward addendum in the correction pack (unit log 282 vs 283 / 19 files; empty typecheck log; run2 failure narrated); sealed packs untouched |

Explicitly deferred (recorded findings, not silent "fixed" claims): phone-width
cart navigation, global-error page, DST policy / 24 h window form, tombstone
re-create, duplicate-id hardening, Dashboard editor / media publisher, real
ordering.
