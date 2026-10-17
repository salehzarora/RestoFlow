# WEB-ORDERS-001 Edge API

## BIZBOT-STOREFRONT-MANUAL-ORDER-PILOT-001 — expiring manual website pilot

Default OFF. `WEB_ORDERS_PILOT_ENABLED=true` routes only `mapsburger` submissions
to service-only `submit_web_order_pilot_request` with the same four arguments and
public response shape. General, private-test and manual-pilot gates are mutually
exclusive; more than one enabled gate denies submission. No bearer or permit is
put in the browser. `status` remains independent of all admission gates.

The database, not CORS or the website, authorizes this route. A private,
operator-installed record binds the exact Maps Burger organization, restaurant
and branch, a salted hash of the owner-approved name/normalized E.164 phone,
a server window of at most 15 minutes, and one lifetime successful request.
Migration installation inserts no pilot or channel and relaxes no profile CHECK.
Wrong scope/contact, disabled, future or expired windows cannot admit a new
request. The request identity lock precedes the pilot row and channel locks;
the existing validator, price authority, abuse limits and pending-only writer
are reused. Expiry after delegated writes rolls back requests, events and counters.

The first successful browser submission atomically binds its client/internal
UUIDs, consumes the budget, disables the pilot and disables the branch channel.
Every second UUID is refused. The original payload/capability replay remains
idempotent at the SQL contract after kill/expiry; customer status remains usable
after the Edge pilot gate is also turned OFF. No accepted order or printing is
created by this RPC. The operator must recognize the owner's browser request
before separately authorizing its exact internal target and manual POS Accept.

The public reader preserves all JSON keys and existing browse-only data. Its
ordering bit becomes true only for this active unconsumed scoped pilot, open
service, pickup and a live channel while printing policy is BLOCKED. The client
allows that bit only for Maps Burger; general `LIVE_ORDERING_RELEASED=false`,
delivery and online payments remain unchanged. Menu pages retain the existing
60-second ISR/360-second bounded-stale contract. Verify rendered checkout before
the owner orders; a cached hint cannot bypass the server deadline or atomic kill.

Kill: disable the private pilot and scoped channel, set the Edge pilot flag OFF;
leave consumed identity/status evidence intact. Expiry and the one-request
budget protect intake even if the operator exits before cleanup. Neither kill nor
installation modifies historical holds, canonical orders, print attempts or
device state. Printing remains a separate exact-target-only owner action.

## Existing API and controlled-test contracts

`POST /functions/v1/web-order-submit` accepts JSON with exactly
`action`, `slug`, `request_id`, `status_token`, and (for `submit` only) `order`.
`action` is `submit` or `status`. Unknown and duplicate JSON keys fail at every
depth. Requests are strictly decoded as UTF-8 and streamed with a 32 KiB limit.

The client creates one UUIDv4 request ID and a capability from **32 CSPRNG bytes**
encoded as canonical, unpadded base64url (43 characters). The Edge Function hashes
the canonical token's UTF-8 bytes with SHA-256 and sends only the lowercase hex
digest to PostgREST. The raw token must remain private and is never returned or
logged. An ID alone does not authorize a status read.

`order` contains only `order_type: "takeaway"`, `customer: {name, phone}`,
`items: [{menu_item_id, quantity, modifiers: [{modifier_option_id, quantity}], notes?}]`,
and `notes`. Omitted `notes` and `modifiers` normalize to `""` and `[]`. Names trim
to 1–80 Unicode characters without controls; phone numbers contain `+` followed
by 8–15 digits with a nonzero first digit. Notes allow at most 500 Unicode
characters, LF, and no other C0 controls. Item and modifier quantities are
integers 1–20; an order has 1–20 lines and at most 50 item units; each line has at
most 20 distinct modifier options. Money, currency, tax and tenant/branch IDs
are never client authority.

Each optional item `notes` must be a string of at most 140 Unicode scalar values
before trimming. LF is allowed; all other C0/C1 controls and unpaired surrogates
are rejected. Boundary whitespace uses JavaScript `trim`; interior whitespace
and LF are preserved. Empty or omitted item notes normalize to an absent key,
preserving compatibility with old note-free payloads and frozen quotes. Invalid
or oversized notes fail; they are never truncated. Item notes participate in the
normalized idempotency identity and immutable server-priced snapshot, but never
change authoritative pricing. Lines remain distinct, including equal products
and modifiers with different notes. Order-level `order.notes` stays independent.
Trusted POS acceptance revalidates the frozen notes with the current quote and
passes them to the existing canonical `order_items.notes` field, which existing
KDS and kitchen dispatch readers consume.

The server uses `SUPABASE_URL` and the platform-injected
`SUPABASE_SERVICE_ROLE_KEY` for exactly one public-schema RPC call per request:

- `submit_web_order_live_request(p_slug, p_client_request_id, p_status_token_hash, p_order)`
  for ordinary admission under BIZBOT-MAPSBURGER-ALWAYS-ON-WEB-ORDERS-001.
- `get_web_order_request_status(p_slug, p_client_request_id, p_status_token_hash)`
- `submit_web_order_test_request(...)` only for the separately authorized,
  disabled-by-default controlled-test permit described below.

Ordinary customer authorization and API key headers are ignored. A controlled
test uses the private Authorization credential described below; it is never
forwarded to PostgREST. Fetch disables redirects
and has a 10 second timeout. There are no automatic RPC retries. `submit` is
disabled unless `WEB_ORDERS_ENABLED` is exactly `true`; the independent database
channel gate is also disabled by default. `status` remains available while the
Edge submit gate is disabled. RPC execution is granted only to `service_role`;
anonymous gateway access does not grant database RPC access.

The live RPC is default OFF and pins the exact Maps Burger published branch to
private persistent rollout authority. It delegates the existing trusted pricing,
validation, quotas and idempotency contract, then atomically enrolls only fresh
live requests. It has no private-contact or one-request budget. Intake OFF closes
new admission while retaining capability status and exact replay. The existing
service-only `submit_web_order_request` remains an internal delegated contract;
the general Edge route no longer invokes it directly. See the
[persistent rollout and OFF runbook](../../../docs/MAPSBURGER_ALWAYS_ON_WEB_ORDERS.md).

Only the exact `WEB_ORDERS_ALLOWED_ORIGIN` is allowed (default
`https://menu.bizbot.systems`); absent Origin permits server calls. CORS is not
authentication. Responses are `no-store`. The public success shape is
`{ok:true, request_id, status, expires_at, totals:{currency_code:"ILS", subtotal_minor, tax_total_minor, grand_total_minor}, replayed}`.
Statuses are `pending`, `expired`, `accepted`, `rejected`. Public results are
explicitly projected so customer data, internal IDs, credentials and tokens
cannot escape through extra upstream fields.

Known database business failures return `{ok:false,error}` with HTTP 400
(`invalid_request`), 404 (`not_found`), 409 (`idempotency_conflict`), 422
(`item_unavailable`, `modifier_selection_invalid`, `menu_unavailable`), 429
(`rate_limited`, `capacity_reached`), or 503 (`ordering_unavailable`).
Malformed local input uses fixed 400/413/415 codes; origin failures use 403 and
unsupported methods use 405.

After a submit RPC transport error, timeout, non-success HTTP response, or invalid
upstream result, HTTP 502/503 returns
`{ok:false,error:"submission_outcome_unknown",request_id,uncertain:true}`.
The client retains the **same request ID, capability and normalized order** for
retry, or uses `status`; it must not create a fresh ID to recover an unknown
outcome. A status transport failure returns `status_unavailable` with the request
ID and `uncertain:false`. Upstream exception text and SQL diagnostics are opaque.

Offline tests (no real credentials, network or database):

```sh
node --test supabase/functions/web-order-submit/test/*.test.mjs
```

The focused SQL suite is `supabase/tests/web_orders_001_test.sql`. A separate
two-session concurrency proof clones a prepared migration-only test database:

```sh
node supabase/functions/web-order-submit/test/run-sql-concurrency.mjs --container LOCAL_NETWORK_NONE_POSTGRES --template PREPARED_TEST_DB
```

It refuses remote Docker contexts, networked containers and published ports, and
drops only its generated disposable clone. The optional native mode is restricted
to the task's portable PostgreSQL runtime under `build/local-pg17`, loopback port
55437 and the matching data directory. Neither test mode can target hosted data.

`supabase/tests/web_orders_checkout_001_item_notes_test.sql` verifies item notes
from submission through immutable pricing, POS inbox, acceptance, canonical rows,
KDS reads and kitchen dispatch, plus note-free compatibility. The additive checkout
migration also exposes existing modifier `allow_quantity` and `max_quantity`
constraints through `storefront_menu`; the pricing RPC remains authoritative.

Hosted migrations, function deployment, and ordering activation remain separate
owner-controlled rollout steps. Pending submissions create no canonical orders;
only the existing trusted POS acceptance invokes the canonical order path.

## STOREFRONT-ROLLOUT-001C-PREP — private single-request permit

Preparation adds no hosted activation. Normal `WEB_ORDERS_ENABLED` admission is
unchanged. While it is OFF, a submit can enter the controlled-test path only when
`WEB_ORDERS_TEST_ENABLED` is exactly `true` and `WEB_ORDERS_TEST_PERMIT` is a
complete JSON object with exactly these keys:

```text
slug, organization_id, restaurant_id, branch_id, request_id,
not_before, expires_at, authorization_sha256, status_token_sha256, order_sha256
```

If both the general and controlled-test gates are `true`, all submissions fail
closed. A test permit must never silently coexist with unrestricted admission.

The slug must be `mapsburger`; scope UUIDs must be non-nil; the request UUID must
be v4. Dates are canonical UTC ISO instants with milliseconds and `Z`, with a
positive window of at most 15 minutes. Every digest is lowercase SHA-256 hex.
`Authorization: Bearer <credential>` carries 32 CSPRNG bytes in canonical
unpadded base64url. Its digest must match `authorization_sha256`; the separate
customer capability must match `status_token_sha256`. The credential and customer
capability must be distinct. `order_sha256` hashes the UTF-8 bytes of
`JSON.stringify(validateRequest(requestBody).order)`, including normalized item
notes, quantities, modifiers and owner-approved test contact details. Do not hash
the raw JSON file: the existing validator supplies defaults and trims item notes.

Missing, invalid, mismatched, not-yet-valid or expired permits all return the
existing opaque `503 ordering_unavailable` without accessing server credentials
or invoking an RPC. CORS/Origin never authorizes a test; existing exact-origin
checks still apply. There is no new route, browser control, client secret, log or
response field. The private bearer is consumed only by the Edge guard.

The private path invokes the service-only `public.submit_web_order_test_request`
with the existing four submit arguments plus `p_test_organization_id`,
`p_test_restaurant_id`, `p_test_branch_id`, `p_test_request_id`,
`p_test_not_before`, and `p_test_expires_at`, all from server configuration.
Its private SQL body checks the full authoritative profile scope under a lock,
the exact UUID and the deadline after waiting for locks; it delegates to the
existing submit implementation. Expiry after delegation rolls back its effects.
The ordinary submit/status RPC signatures, pricing, quotas, private table ACLs,
POS authorization and canonical order/dispatch writer remain unchanged.

The existing SQL channel must separately admit this branch for a new request.
No code creates or enables a channel. Public profile CHECKs, public ordering
advertisement and `LIVE_ORDERING_RELEASED=false` remain unchanged. The database
unique identity and existing payload/capability checks make exact replays durable
across Edge instances; no worker-memory counter is used. A different UUID, slug,
payload or capability cannot use the permit. After permit expiry or removal,
ordinary capability status remains available; no new UUID may be generated to
recover an uncertain response.

The operator procedure and switch-off instructions are in
[`docs/STOREFRONT_ROLLOUT_001C_PREP.md`](../../../docs/STOREFRONT_ROLLOUT_001C_PREP.md).
