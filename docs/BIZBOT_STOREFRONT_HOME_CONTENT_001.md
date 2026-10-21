# BIZBOT-STOREFRONT-HOME-CONTENT-001 — first slice of Issue #360

Owner-approved parent: BIZBOT-STOREFRONT-COMPLETION-001 / GitHub Issue #360.
Baseline: `e9aec5405c5a9109458a8377111e75d80b9f6b1b`.
This contract is recorded before application, API or SQL implementation. It
authorizes local implementation within the approved roadmap; independent
review/CI, exact-head owner merge approval, RLS/security signoff and hosted
application/deployment are separate gates. No production operation is performed
by recording it.

## First-slice scope

Keep the existing Storefront and its approved component order. Add real
Dashboard editing for three presently unconfigurable Home values:

| Profile column | Type | Maximum Unicode code points | Empty behavior |
| --- | --- | ---: | --- |
| `hero_headline` | nullable plain text | 120 | existing tagline/name fallback |
| `hero_subline` | nullable plain text | 180 | omit row/rule |
| `announcement_text` | nullable plain text | 240 | omit announcement |

Trim outer whitespace and normalize blank text to null. Reject wrong types,
overlong values and ASCII controls. Text is merchant-owned, escaped, direction
isolated and never interpreted as HTML/Markdown, URLs, pricing or order authority.
Do not strip literal characters from existing merchant names. Existing logo,
hero image, primary/accent, preset, card mode and motion controls remain the only
authority for their presentation. A narrow-header layout fix must preserve
controls, full stored names and accessible names without overlap.

Story/promo editing, category photos, featured items, Call restaurant, checkout
copy, ETA and receipt formatting are later separately reviewed slices. Do not
invent promotion prices, rankings, copy or media to fill missing modules.

## Existing profile and manager authority

Add only these nullable columns to `public.restaurant_storefront_profiles`.
Retain forced RLS, existing tenant/restaurant/branch constraints and grants.
There is no new customer table, queue or per-tenant/device configuration.

Add a narrow home-content setter using the existing authenticated manager-rank
check, restaurant-then-profile lock ordering, shared profile version/CAS,
management request ledger/fingerprinting and audit helpers. Its request identity
binds organization, restaurant, expected profile version and the complete exact
three-key content object (each value string or null). Unknown/missing keys fail.
Fingerprint the complete raw object before text normalization; changing even a
normalization-equivalent value under the same request identity is a mismatch.
Revalidate the current authenticated manager's authority before returning a
replay. Mutation ACLs are authenticated-only with fixed qualified references and
an empty search path; revoke default PUBLIC/anonymous execution.
Identical replay returns the original result; changed content/scope/version under
the same identity fails. No direct browser table writes or service-role client.
Update only the three content columns and the profile version; preserve all
other profile fields and media associations. A base-profile edit and a content
edit share the same CAS version and cannot silently overwrite each other.
The narrow setter updates an existing profile only. A missing profile returns
typed `not_found`; normal profile creation must happen through the existing
profile workflow, never by silently inserting/resetting ordinary fields here.

Do not modify the existing generic profile setter's allowlist, fingerprints or
replay semantics. Its explicit column updates preserve the new nullable fields.
The existing manager getter includes profile columns dynamically. Older clients
ignore new read fields and retain their ordinary update contract. The new
Dashboard model accepts missing fields from an older backend and does not claim
that unsupported content saves succeeded.

## Public menu compatibility

Preserve the existing `public.storefront_menu` signature and response bytes/shape.
Its current strict live decoder must not receive unknown fields unexpectedly.
Add a versioned companion `public.storefront_menu_v2` with the same slug argument.
It delegates to the existing authoritative public menu exactly once, preserves
failure envelopes, published tenant/branch admission, pricing/media constraints
and ordering/service state, then adds one bounded `home_content` object on
success. The object contains `hero_headline`, `hero_subline` and
`announcement_text`, each string or null. Resolve the content only from the same
published restaurant/profile scope established by that menu result; never from
untrusted IDs supplied by a visitor. No private owner contact or internal IDs.
Declare the companion read STABLE and prove same-statement MVCC snapshot
semantics. The existing menu exposes no internal scope identifiers: use its
validated returned slug with the full published organization/restaurant/branch
ancestry checks under that same snapshot, not a second independently refreshed
read. Refuse an inconsistent/missing scoped profile instead of mixing results.
Public-read execution ACLs must exactly match the current menu: anonymous and
service-role execution, with authenticated execution still denied. Do not grant
table access or mutation authority.

New Storefront code uses the companion read after the backend is installed. Its
decoder validates the exact additive object and maps only these fields to the
existing campaign/announcement components. Missing/empty values keep the honest
fallback behavior. Announcement suppression while closed/paused is unchanged.
There is no alternate order transport or decision/printing authority.

## Rollout and rollback

1. Review/CI and exact-head owner approval of this slice.
2. Apply only the additive migration via the approved exact-version process;
   verify schema/history/ACL/RLS and that the old menu contract remains intact.
3. Deploy the compatible Dashboard and new Storefront reader on the actual
   separately controlled menu project. No Git reconnection or deployment is
   implicit in this local implementation task.
4. Owner edits real content through the authorized Dashboard; verify fresh public
   data after the existing 60-second revalidation/cache policy. Test Restaurant B
   independently without hardcoded tenant IDs or synthetic production orders.

Old clients and the current live website remain on the existing RPC until the
new reader is deployed. Do not deploy a new-RPC-only reader before its backend.
Rollback reuses the previous frontend artifacts; retain additive columns and
audit/idempotency evidence. Do not drop data or rewrite migration history.

## Verification

Synthetic SQL/RLS tests: bounds/types, empty values, cross-tenant and employee
denials, CAS conflicts, exact replay/mismatched replay, atomic rollback, audit,
old generic setter preservation, old/new public contract and unpublished scope.
Dashboard tests: real repository request identity, getter/model compatibility,
save/conflict/failure UI and AR/HE/EN labels. Storefront tests: strict decoding,
fallbacks, merchant text escaping/isolation, media/price/service invariance,
header control geometry at 360–430/834/1280 and AR/HE/EN; capture actual browser
output, not CSS assertions alone. No calls, orders, acceptance, prints or device
actions during this slice.

## Protected boundaries

Preserve website ordering, notifications, Cron, v68 transport forwarding,
single-winner acceptance/printing, pairings and all 625 historical holds.
No POS/KDS/APK changes. The ETA contract must be documented separately before
its cross-stack implementation; this content API supplies no estimates.

Payment workstreams own their existing changes in shared contract/operations
documents. This slice uses this dedicated contract and one additive decision
index entry; it does not edit those payment worktrees or their D-051/D-052 IDs.
