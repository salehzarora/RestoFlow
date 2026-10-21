# Storefront restaurant contact and checkout copy

Work ID: **BIZBOT-STOREFRONT-CONTACT-CHECKOUT-001**. Parent: Issue #360,
`BIZBOT-STOREFRONT-COMPLETION-001`. Base: `a0451af0dd947eb909eb2416794c62a431a43761`.

This independent Storefront slice follows the deployed Home-content work in
PR #361. It introduces no database, Dashboard, shared-package, Edge, POS, payment
or printing change. Deployment and real-device telephone acceptance remain
separate from local implementation and review.

## Public restaurant contact

The existing Dashboard **public phone** field is the sole authority:
`restaurant_storefront_profiles.public_phone` → public menu `restaurant.phone`
→ decoded `tenant.phone`. Home displays a **Call restaurant** action beside the
service information. The live post-submit/status view receives a separate
`publicPhone` scalar from that same tenant resolution. The action does not depend
on an order being pending, accepted, rejected, expired, recovered or uncertain.
It does not alter polling, decisions, recovery, retries or customer reasons.

`restaurantPhoneHref` validates the existing published-phone SQL grammar:

```text
^(\+[1-9][0-9]{6,14}|0[0-9]{1,2}[- ]?[0-9]{3}[- ]?[0-9]{4})$
```

The existing public contract is intentionally broader than customer checkout
validation: international contacts can have 7–15 digits and local legacy shapes
are retained. The helper does **not** use `normalizeCheckoutPhone`, infer a
country or prefix, assert number allocation, or rewrite the published value.
After full validation, only ASCII spaces/hyphens are removed from the `tel:`
target. The original number remains visible, selectable and isolated left to
right. Missing or invalid public contact yields no telephone action, with no
private-owner or customer-number fallback.

An additional ASCII-character allowlist rejects controls (including final CR/LF,
which JavaScript `$` alone would not reject), Unicode whitespace/bidi marks,
schemes, percent escapes, extensions, parameters and query/fragment injection.
The component renders a plain anchor; it has no effect, click handler, automatic
dial, clipboard, permission request, logging or persistence. Existing Home/status
button styles provide 44/48-pixel minimum-height targets without another style
bundle. AR/HE/EN labels remain localized. Shared `RequestTenant`, request
snapshots, handoffs, capabilities and customer storage remain unchanged.

The public phone was absent for both published tenants when this slice started.
A manager must save their intended customer-facing number through the existing
Dashboard before a live action can appear. Do not manufacture merchant content
or fall back to any private number to make acceptance look complete.

## Checkout copy

The phone field retains its visible label, LTR entry, telephone keypad hint,
autocomplete, raw editable draft value and existing first-invalid-field focus.
It has no format/example placeholder or persistent explanatory text. After a
blocked continuation attempt, an invalid number gets a concise localized error
with `role="alert"`; `aria-describedby` exists only while that actual error is
rendered. Correction removes both the error and its description reference.

Customer-phone normalization, validation, canonical E.164 outgoing payload,
immutable request identity/body, retry/reconciliation and memory-only customer
data are unchanged. A telephone action uses the published restaurant contact,
even when the customer's draft or submitted phone differs.

## Verification and acceptance

Run the existing Storefront unit/source guards and typecheck, fixture build,
snapshot/output/first-load budgets, deployment-filter proof and
`node scripts/verify-web-orders-checkout.mjs`. The latter runs the actual live
components against a loopback synthetic menu RPC; every browser Edge request is
intercepted in memory and all other remote traffic is blocked. No production
order or request is created. Tests inspect telephone targets without clicking
them or launching a dialer.

Focused evidence covers public-contact compatibility/injection/null handling,
tenant separation, Home at phone/tablet/desktop widths, all four live order
states, recovery/not-found/unknown/unavailable views, conditional phone errors in
AR/HE/EN, original editable Review phone, canonical outgoing payload and exact
retry identity. Existing privacy and source-boundary guards remain mandatory.

After independent review and owner-authorized deployment, verify the intended
manager-published number on Home and the customer's own live status page. A
later owner-operated click must confirm the correct dialer target; local href
inspection does not establish that physical result. Do not submit customer test
orders or claim live telephone acceptance from synthetic tests.

## Remaining parent work

- Home headline/subline/announcement controls were delivered in PR #361;
  additional promo/story/category/featured-image controls remain separate
  reviewed contracts. This slice adds no competing phone setting.
- Cashier-configured ETA needs an authoritative end-to-end order contract.
  No estimated time is invented here.
- Local-format customer phone on receipts belongs to the separate POS/printing
  scope. Do not change saved order data, renderer semantics or protected prints
  as part of this slice.
- The concurrent payment documentation and printer workstreams, including
  PR #314/#315, remain outside this change.
