# WEB-ORDERS-CHECKOUT-001 — owner-approved execution packet

Baseline: `59f3eb5976b8f8cfa52e61ddc475464b3ede6f0e` (PR #322 Normal Merge).
Branch: `feat/WEB-ORDERS-CHECKOUT-001-checkout`.
Decision authority: GPT + project owner; Codex is the sole executor.

## Approval and scope

Owner authorization on 2026-10-14 explicitly approves direct browser HTTPS POST
only to the configured Supabase `web-order-submit` endpoint, a CSP exception for
that exact origin, capability-only tab-session recovery, and backward-compatible
per-item notes across HTTP validation, SQL snapshots/revalidation and POS
acceptance. No Next.js API routes, generic proxies, new dependencies, online
payment, delivery, or visual redesign.

Recovery may persist only canonical slug, UUIDv4 request ID, a Web Crypto
256-bit capability and creation/expiry metadata, for at most 24 hours. Customer,
cart, modifiers, notes and the frozen submission payload remain memory-only.
After uncertain submission, reconcile status before an explicit retry with the
same ID/token/body. After reload without the body, recover status only.

Notes must remain distinct per line, bounded and validated without truncation;
order notes remain independent. Canonical order writer and KDS/printer engines
are unchanged. Submission creates pending requests only; trusted POS acceptance
is the sole canonical-order boundary.

## Isolation and verification

Fresh origin/main verified. PR #314/#315 and dirty worktrees have zero exact
file overlap with the planned checkout, Edge validation and inbox-note scope.
Parallel Codex subtasks use separate branches/worktrees. Primary checkout and
Claude Code workstreams are not edited.

Focused checks cover payload/price authority, modifiers/quantities/notes,
identity/retry/reload recovery, capability/tenant isolation, terminal states,
no premature/duplicate canonical or kitchen dispatch, accepted canonical notes,
AR/HE/EN responsive UI, exact CSP, credential and storage boundaries. One
independent review and normal GitHub CI follow implementation.

## Activation and release boundary

Live Storefront remains browse-only. No hosted migrations, Edge deployment,
real customer test orders, channel/ordering/delivery changes, production
configuration changes, merges or production deployment are authorized. The PR
contains source/configuration for separately approved future activation only.
Hosted dependencies: WEB-ORDERS-001, POS-ONLINE-INBOX-001 and this task's additive
migration; compatible web-order-submit deployment; separate rollout approval.

The implementation and focused verification are complete. Merge and hosted
rollout still require separate owner authorization and security sign-off.


## Verification findings corrected within this implementation

- Independent review found that storage-unavailable copy could falsely claim an
  uncertain/already accepted request had not been sent. Availability copy is now
  neutral in AR/HE/EN; known status and uncertainty remain explicit.
- Initial checkout first-load JS exceeded the existing 690,000-byte ceiling.
  A server-only static split still preloaded both live and fixture clients.
  The correction uses client loading boundaries at three fixed in-repository
  imports: FlowEntry → FlowRuntime / LiveFlowRuntime, and CheckoutEntry →
  LiveCheckoutProvider. The engine, local source contract and build-input audit
  share one exact file/target policy and inspect these modules; computed loaders,
  additional paths/files, duplicate loads and require remain rejected. No Next
  configuration hash, package/dependency, API route or budget ceiling changes.
- First-load measurement now counts script preload/modulepreload transfers as
  well as script tags, with URL deduplication and separate speculative prefetch.
  A focused negative-control-style measurement test proves preload-only script
  bytes count. This prevents an apparent pass obtained by moving script tags.

## Completed implementation and security proof

- Direct browser POST uses only the exact configured HTTPS Edge endpoint,
  credentials omitted, redirects rejected and no-store. CSP permits only the
  exact project origin. No Next API route, generic proxy or browser API key.
- Web Crypto supplies UUIDv4 and 32 random capability bytes. Recovery records
  contain exactly slug/request ID/capability/creation/expiry; maximum retention
  is 24 hours. Contact information, cart, modifiers, notes and submission body
  remain in memory. Reload recovers status without reconstructing a write.
- Submission uncertainty triggers status reconciliation before an explicit
  identical retry. Accepted, rejected and expired transitions use real backend
  results; pending never implies acceptance. A terminal replay cannot dispatch
  again. The independent live release gate remains false.
- Optional item notes are raw-length bounded to 140 Unicode code points,
  validated without truncation, normalized consistently and retained in request
  identity, immutable quote and revalidation. Distinct lines remain distinct.
  Trusted POS acceptance carries each note into existing order_items.notes;
  order-level notes remain separate. A real synthetic local device/PIN acceptance
  and KDS sync_pull prove item.note and order_note in money_free_payload.
- The additive migration also exposes existing modifier quantity bounds in the
  public reader. Old catalogs lacking both fields remain browseable; half or
  malformed extensions fail closed. Existing tenant grants/admission rules,
  canonical writer, KDS/printer engines and old migration files are unchanged.

## Focused verification results

| Check | Result |
| --- | --- |
| Storefront unit/contract/recovery/UI suite | 350 passed, zero skips/failures |
| TypeScript and source-input containment | Passed; 192 files inspected |
| Edge validation/handler | 26 passed |
| New notes SQL/security/integration | 54 passed |
| Existing pending web-order SQL | 174 passed |
| Existing POS inbox SQL | 86 passed |
| Existing public Storefront reader SQL | 121 passed |
| POS notes decoder/widget AR/HE/EN | 4 passed; scoped analysis clean |
| Affected deployment-filter regression | 43 passed |
| Served-output/header/budget tests | 28 passed |
| Three-project real-shell filter proof | Passed |
| Release fixture build and server snapshot | Passed; 36 canonical routes + 404 |
| Provider-shaped live release build | Passed; no tenant/request prerender |
| Final Chromium checkout/status run | 14 passed; 27 screenshots; zero hosted requests |
| Money, secret and hardcoded-string guards | Passed |
| Dart formatting and git diff checks | Passed |

The SQL checks used a fresh local PostgreSQL 17 cluster and synthetic data only.
No hosted migration, function deployment, test order or production mutation was
performed. Existing JS ceilings remain 690,000 raw / 200,000 Brotli bytes.
Final script + script/modulepreload URL unions, deduplicated and compressed per
asset at fixed Brotli quality 11:

| Release measurement | Raw bytes | Brotli bytes |
| --- | ---: | ---: |
| Largest fixture route | 680,732 | 182,204 |
| Synthetic live menu | 664,406 | 178,705 |
| Synthetic live review | 682,804 | 183,700 |

Fixture/provider builds use the default release compiler. The isolated-copy
Chromium harness uses Next 16.3.5 release Webpack with node_modules junctions,
synthetic loopback catalog reads and exact Edge interception; it checks actual
live-page initial scripts/preloads against the same ceilings. It does not call
hosted services or change the tracked release gate. Brotli figures are local
per-response compression estimates, not observed hosted transfer bytes.

Existing CSS-UI001-01 remains explicitly reported: 32 listed routes exceed the
original 70,000-byte raw CSS target but meet the previously owner-approved
100,000-byte ceiling and unchanged 14,000-byte Brotli limit. No new waiver or
limit increase. Local advisors reported zero errors and four pre-existing
mutable-search-path warnings in untouched functions.

## Independent review and isolation

One independent review approved the implementation and bounded correction delta
through bb6afbe8f1e887e8aeecf05d476e6d1e146456a4. The actual availability-copy
finding was fixed; no open Blocker/Major findings. Reviewer independently passed
56 checkout tests, 26 Edge tests, then 2 loader guard and 7 contract/preload
correction tests plus the 192-file input audit. Final Chromium proof was reviewed.
No recursive review, Canary, Seal or unrelated local full-suite cycle.

Final fetch still reports origin/main at the baseline. PR #314/#315 heads remain
unchanged and have zero file overlap. A read-only inventory compared all 91 task
paths against 77 external worktrees: 14 dirty, 63 clean, zero errors and zero
dirty-file overlaps. Primary checkout and Claude Code worktrees were not edited.

## Evidence locations

Under the principal worktree, build/web-orders-checkout-001 contains final unit,
fixture/live release build, snapshot, output, first-load, filter and guard logs.
The final synthetic browser evidence is:

`C:/Users/saleh/Desktop/ClaudeAi/RestoFlow/worktrees/WEB-ORDERS-CHECKOUT-001-client/build/web-orders-checkout-001/browser-1791939028311-85474d16`

It contains summary.json, live-js-budgets.json, results.json, report/ and
screenshots/. Tracing is off. Automatic approval review rejected deletion of
earlier ignored synthetic test traces as "blocked by policy"; those local-only
artifacts remain isolated and are not committed. They contain no real customer
credentials or production capability.

## Hosted rollout dependencies — not executed

1. Separately approve/apply pending migrations in order:
   20261013174657_web_orders_001_pending_requests,
   20261013215529_pos_online_inbox_001, then
   20261013235300_web_orders_checkout_001_item_notes.
2. Separately authorize a compatible web-order-submit deployment with the
   existing request-origin/CORS and backend admission protections intact.
3. Coordinate compatible POS inbox and customer checkout releases; perform
   separately authorized production acceptance before enabling either the
   source release gate or restaurant ordering admission.
4. Keep ordering and delivery OFF until explicit rollout approval. Online
   payment and delivery integration remain out of scope.

GitHub CI status is reported on the implementation PR. This packet does not
claim hosted acceptance or authorize merge/deployment.

## Exact changed-file scope

91 files: 72 Storefront files, 6 Supabase files, 4 POS inbox-note files,
7 architecture/execution documents and 2 deployment-filter guard/test files.
The exact baseline-to-head list follows; all paths are repository-relative.

```text
apps/pos/lib/src/data/online_order_inbox.dart
apps/pos/lib/src/widgets/online_order_inbox_sheet.dart
apps/pos/test/online_order_inbox_repository_test.dart
apps/pos/test/online_order_inbox_widget_test.dart
docs/API_CONTRACT.md
docs/DECISIONS.md
docs/DOMAIN_MODEL.md
docs/IMPLEMENTATION_CHECKLIST.md
docs/SECURITY_AND_THREAT_MODEL.md
docs/WEB_ORDERS_001.md
docs/WEB_ORDERS_CHECKOUT_001.md
storefront/README.md
storefront/app/(root)/s/[slug]/layout.tsx
storefront/app/ar/s/[slug]/layout.tsx
storefront/app/en/s/[slug]/layout.tsx
storefront/app/he/s/[slug]/layout.tsx
storefront/scripts/audit-inputs.mjs
storefront/scripts/audit-output.mjs
storefront/scripts/budgets.mjs
storefront/scripts/measure-firstload.mjs
storefront/scripts/verify-web-orders-checkout.mjs
storefront/src/cart/CartMemoryProvider.tsx
storefront/src/cart/cartModel.ts
storefront/src/cart/cartStorage.ts
storefront/src/cart/useCart.ts
storefront/src/i18n/orderCopy.ts
storefront/src/i18n/orders.ts
storefront/src/i18n/productNotes.ts
storefront/src/money/pricing.ts
storefront/src/orders/contract.ts
storefront/src/orders/controller.ts
storefront/src/orders/customer.ts
storefront/src/orders/identity.ts
storefront/src/orders/index.ts
storefront/src/orders/json.ts
storefront/src/orders/notes.ts
storefront/src/orders/payload.ts
storefront/src/orders/recovery.ts
storefront/src/orders/transport.ts
storefront/src/orders/validation.ts
storefront/src/source/live/adapter.ts
storefront/src/source/live/decode.ts
storefront/src/source/live/ordering.ts
storefront/src/source/types.ts
storefront/src/ui/storefront/StorefrontRuntime.tsx
storefront/src/ui/storefront/cart/CartContext.tsx
storefront/src/ui/storefront/cart/CartRuntime.tsx
storefront/src/ui/storefront/checkout/CartScreen.tsx
storefront/src/ui/storefront/checkout/CheckoutEntry.tsx
storefront/src/ui/storefront/checkout/DetailsScreen.tsx
storefront/src/ui/storefront/checkout/FlowEntry.tsx
storefront/src/ui/storefront/checkout/FlowRuntime.tsx
storefront/src/ui/storefront/checkout/FlowScreen.tsx
storefront/src/ui/storefront/checkout/LiveCheckoutProvider.tsx
storefront/src/ui/storefront/checkout/LiveFlowBody.tsx
storefront/src/ui/storefront/checkout/LiveFlowRuntime.tsx
storefront/src/ui/storefront/checkout/LiveOrderProvider.tsx
storefront/src/ui/storefront/checkout/LiveReviewScreen.tsx
storefront/src/ui/storefront/checkout/ReviewScreen.tsx
storefront/src/ui/storefront/checkout/draft.ts
storefront/src/ui/storefront/checkout/flow.module.css
storefront/src/ui/storefront/checkout/flowParts.tsx
storefront/src/ui/storefront/checkout/validation.ts
storefront/src/ui/storefront/product/ProductSheet.tsx
storefront/src/ui/storefront/product/product.module.css
storefront/src/ui/storefront/request/LiveRequestRuntime.tsx
storefront/src/ui/storefront/request/liveRequest.module.css
storefront/tests/browser/web-orders-checkout-001.spec.ts
storefront/tests/contract.test.mjs
storefront/tests/headers.test.mjs
storefront/tests/output/output.test.mjs
storefront/tests/sf-firstload-preloads.test.mjs
storefront/tests/sf-flow.test.mjs
storefront/tests/sf-live.test.mjs
storefront/tests/sf-source-rules.test.mjs
storefront/tests/sf-web-orders-controller.test.mjs
storefront/tests/sf-web-orders-fixtures.mjs
storefront/tests/sf-web-orders-payload.test.mjs
storefront/tests/sf-web-orders-recovery.test.mjs
storefront/tests/sf-web-orders-transport.test.mjs
storefront/tests/sf-web-orders-ui.test.mjs
storefront/tests/support/envelope.mjs
storefront/vercel.json
supabase/functions/web-order-submit/CONTRACT.md
supabase/functions/web-order-submit/test/handler.test.mjs
supabase/functions/web-order-submit/validation.mjs
supabase/migrations/20261013235300_web_orders_checkout_001_item_notes.sql
supabase/tests/storefront_read_001_test.sql
supabase/tests/web_orders_checkout_001_item_notes_test.sql
tools/vercel/ignore-build.mjs
tools/vercel/ignore-build.test.mjs
```
