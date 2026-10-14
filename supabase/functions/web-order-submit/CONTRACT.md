# WEB-ORDERS-001 Edge API

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
`SUPABASE_SERVICE_ROLE_KEY` for exactly one of these public-schema RPC calls:

- `submit_web_order_request(p_slug, p_client_request_id, p_status_token_hash, p_order)`
- `get_web_order_request_status(p_slug, p_client_request_id, p_status_token_hash)`

Customer authorization and API key headers are ignored. Fetch disables redirects
and has a 10 second timeout. There are no automatic RPC retries. `submit` is
disabled unless `WEB_ORDERS_ENABLED` is exactly `true`; the independent database
channel gate is also disabled by default. `status` remains available while the
Edge submit gate is disabled. RPC execution is granted only to `service_role`;
anonymous gateway access does not grant database RPC access.

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
