# WEB-ORDERS-001 — pending customer orders

Owner-authorized backend foundation. This implementation is isolated from POS,
KDS, printing and Storefront presentation. It does not activate ordering, apply
hosted migrations, deploy functions, or create canonical orders.

## Boundary and activation

The customer API creates a **pending request**, never an `orders` row. The new
`web-order-submit` Edge Function is an anonymous HTTP boundary; its gateway JWT
check is intentionally off. It uses the platform-injected service-role credential
only on the server to call two exact database RPCs. Customer Authorization headers
are never forwarded as that credential. Both RPC layers deny PUBLIC, anon and
authenticated; only service_role can execute them. The existing anonymous database
allowlist remains exactly `storefront_menu(text)`.

Submission requires BOTH `WEB_ORDERS_ENABLED=true` and an explicitly enabled
`web_order_channel_settings` row for the profile's current full branch scope.
The migration creates no enabled channel. Existing profile CHECKs, public reader,
checkout routes and ordering/delivery flags stay unchanged and OFF. Future POS
acceptance and customer checkout must land before a separately approved activation.

## Customer contract

POST JSON to `/functions/v1/web-order-submit`. Submit keys are exactly `action`
(`submit`), `slug`, `request_id` (client-generated UUIDv4), `status_token` (32
cryptographically random bytes, canonical unpadded base64url), and `order`:

```json
{
  "order_type": "takeaway",
  "customer": {"name": "Customer", "phone": "+972501234567"},
  "notes": "",
  "items": [{"menu_item_id": "UUID", "quantity": 1, "modifiers": []}]
}
```

A modifier contains only `modifier_option_id` and `quantity`. No price, total,
discount, tax, currency, tenant, branch, size/variant, dispatch or payment field is
accepted. The API normalizes omitted notes/modifiers to empty values; SQL validates
the normalized shape independently. Caps: 32 KiB HTTP body, 20 lines, 50 total
units, 20 options per line, quantity 1–20, name 80 characters, notes 500 characters,
E.164 phone. Duplicate option rows are refused instead of permitting quantity-cap
bypass. JSON duplicate keys and invalid UTF-8 are rejected at HTTP ingress.

Status uses POST with exactly `action` (`status`), `slug`, `request_id`, and
`status_token`. Never put the capability in a URL, query string, log or analytics.
Only SHA-256 of the canonical token reaches the database. Status is uniform
`not_found` for unknown requests, wrong tokens, wrong slugs and expired capabilities.
It exposes only the caller's request reference, effective state, expiry and totals;
no customer PII, internal scope IDs, raw token, canonical order ID or other request.
Responses are `no-store`. The reference is valid for 24 hours. A pending request
expires after 15 minutes, even if no job has materialized its expired state.

## Pricing and eligibility

Scope comes only from the published slug and its current Storefront branch.
Pricing uses the same currently served live catalog as `storefront_menu`: active,
undeleted, tenant/restaurant/branch-visible items, categories, groups and options;
sold-out items and negative option deltas are refused. Current DB prices are
snapshotted server-side. For each line:

`quantity * (base_price_minor + sum(option.price_delta_minor * option_quantity))`

Exclusive tax uses the existing pure `app.edit_tax_minor` helper. Unsupported
currency/tax/configuration fails closed. No discounts, payment or delivery fees.
All stored/returned money is integer minor units; total is capped at 10,000,000.

Modifier validation follows the existing kiosk server rules: a single group needs
exactly one distinct option; a required multiple group needs at least one (or its
higher DB minimum); DB min/max count distinct options, including a literal zero
maximum. Per-option quantity requires `allow_quantity` and obeys `max_quantity`.
Impossible configurations are refused. This deliberately does not inherit the
Storefront adapter's permissive min/max normalization. Sizes/variants remain outside
the currently published Storefront catalog and this initial submission contract.

## Idempotency, abuse and audit

Restaurant + request UUID uniquely identifies the request. A transaction advisory
lock and unique constraint serialize retries. Exact normalized body + token hash
returns the original quote; changing either conflicts. A retry never reprices,
duplicates the request, or moves its captured branch. After an uncertain HTTP
outcome, retain the same UUID/token/body, query status, and retry that identity only.
The function does not automatically retry a database write.

Per-branch counters serialize admission and consume at most one bounded settings
row: 60 attempts/minute, 10 new requests/minute, 1,000/day UTC, 50 unexpired pending
requests and three per phone; status is capped at 600 attempts/minute. These are
initial engineering caps, not client claims or IP-header-based authorization.
Invalid/rotating client identities cannot bypass branch-wide admission limits.
Provider-level bot/DDoS filtering remains a rollout concern; this does not add a
challenge provider, new dependency or trusted-client-IP assumption.

The three new tables have forced RLS and no direct app-role grants. Received events
are append-only and contain no PII or capability. Anonymous submissions use their
own event ledger, not a fabricated staff identity in `audit_events`.

## POS-ONLINE-INBOX-001 integration contract

A future authenticated POS endpoint must validate the existing device/PIN session
and derive full scope server-side. It must lock a pending, unexpired request in
that scope, revalidate eligibility/current prices, and either refuse a changed
quote for customer reconfirmation or use the agreed current quote. Acceptance must
create exactly one canonical order through the existing trusted order path and
record its mapping in the SAME transaction. Rejection creates no canonical order.
Only after acceptance may the existing KDS/printer dispatch run. Never manufacture
a device/PIN identity or invoke canonical `submit_order` with customer credentials.

This slice exposes no inbox, accept, reject, canonical-create or kitchen action.
Request identity and quote are immutable; transition constraints reserve accepted,
rejected and expired states for the future trusted integration. Terminal decisions
cannot be reversed, and a canonical mapping must match the full stored scope.

## Verification and release

Focused Node API tests, pgTAP security/pricing/idempotency/expiry/abuse tests,
concurrent retry proof and the affected anonymous-surface/isolation guards.
One independent review and normal GitHub CI precede owner merge approval.
Hosted migration, function deployment, channel enablement and live ordering each
remain separately controlled. No actual customer orders are used in local tests.
