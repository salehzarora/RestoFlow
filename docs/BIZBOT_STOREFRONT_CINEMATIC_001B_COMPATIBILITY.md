# BIZBOT-STOREFRONT-CINEMATIC-001B — versioned read compatibility

Owner-approved scope: PR #379 completion packet, section 7. This correction
preserves the approved appearance design and existing writes while keeping
already-open strict clients usable after new settings have been saved.

## Inventory and contract

Repository migration inventory and the parent release agent's hosted catalog
check found existing content/media v1 and menu v1–v4. Content/media v2 and
menu v5 were absent in the hosted target. Hosted history ended at
`20261102015942`; appearance `20261102140930` was still unapplied. Therefore
only that unapplied migration was amended; no applied SQL file was edited.

| Read | Contract and authority |
| --- | --- |
| `get_restaurant_storefront_content_v1(uuid,uuid)` | Exact legacy document and warning paths; no appearance key, even after clearing. Existing app/public function bodies and ACLs unchanged. |
| `get_restaurant_storefront_content_v2(uuid,uuid)` | Same envelope, principal, role, ancestry and active-profile checks. Optional appearance contains only validated colors, approved font, menu media ID and dim. |
| `list_storefront_content_media_v1(uuid,uuid)` | Exact legacy envelope and usage enums (`promo`, `story`, `category`), unchanged bodies and ACLs. |
| `list_storefront_content_media_v2(uuid,uuid)` | Same tenant/restaurant/branch media selection and ordering; adds only the `menu_background` content usage kind. |
| `storefront_menu_v4(text)` | Exact legacy public projection; unchanged function body and ACL. |
| `storefront_menu_v5(text)` | Existing published-tenant eligibility and one v3 catalog read. Adds optional appearance inside `content_v1` (schema remains 1); replaces private background ID with eligible public derivative URL. |

The new management app bodies remain SECURITY DEFINER with explicit existing
principal/rank/ancestry checks. Their public wrappers are SECURITY INVOKER.
Both layers grant EXECUTE only to authenticated, after explicit revokes from
PUBLIC, anon, authenticated and service_role. The new normalization helper
`app.storefront_content_read_v2(uuid,uuid,uuid,text,text,text,jsonb)` has no
client-role EXECUTE grants. Every new function has an empty search path.
Public menu v5 mirrors v4's exact anon + service_role read grants; it has no
authenticated/PUBLIC grant and exposes no private media ID or storage source.
The six existing exact public-surface guard lists enumerate only the newly
approved `storefront_menu_v5(text)` identity; their guard queries and negative
controls are unchanged. SEO gates and SEO reader contracts are unchanged.

## Writes and retraction

`set_restaurant_storefront_content_v1` retains its existing signature, CAS,
branch conflict, request fingerprint, idempotent ledger and response shape.
The existing appearance merge preserves omitted fields; explicit JSON null
clears a setting. Old documents obtained through v1 may be written after a
new editor save without erasing appearance. The writer's before/after audit
now uses the new complete private read so appearance remains in audit data.

Legacy media lists cannot represent menu-background usage. They omit that
usage without substituting another kind or expanding the old enum. The
existing authoritative `storefront_content_media_in_use_v1` still includes
menu backgrounds, so a legacy client attempting retraction receives the
existing `media_in_use` refusal. Same-source republication repoints the
background through the existing guarded replacement helper.

## Client and release sequence

Dashboard uses content v2 and media v2. Its existing strict decoder recognizes
only the approved optional appearance fields and the approved new usage kind.
Storefront requests menu v5 and uses a dedicated strict v5 decoder. The strict
v4 decoder rejects appearance, while both accept an unchanged legacy document.
Neither reader falls back after a missing API, permission error, network error
or malformed response. The existing uncertain-save reconciliation and retry
identity are unchanged.

Install the reviewed migration first, then the reviewed media publisher if
required, followed by the new Storefront and Dashboard builds. Keep old
readers available throughout. A frontend rollback remains compatible because
legacy reads omit the new fields and legacy writes preserve them. Do not
clear caches, log users out or mutate merchant settings to establish readiness.
Existing ISR/CDN behavior is unchanged; route verification must wait for actual
revalidation and inspect the serving deployment and public read version.

## Provenance and verification

Final SQL file: `20261102140930_bizbot_storefront_cinematic_001b_appearance.sql`.
Final LF SQL SHA-256:
`a276aef4fdd30b35272939e51d649bff3dfeb70b6c806ecb7c2edee94ceb263b`.
This agent applied it zero times locally or hosted. Production application
count must be recorded by the release agent after the approved release gates.

Historical wrapper-only proof still reads commit
`84d73363c218735648ab1b778337fb6ffdebfcd0`, preserves its original SHA-256
`478e950e8e3ac571e439b9dc8a4ae757db7e1e53c234d8f2fb30e9c3343b0462`,
and remains separate from the final SQL fingerprint. The existing disposable
Supabase atomicity runner now verifies rollback and one successful installation
of the appearance column plus all three new public read endpoints. It still
compares whole schema/ACL and migration-history snapshots and has no embedded
transaction wrapper or hosted endpoint.
The final migration sets transaction-local lock acquisition to 5 seconds and
statement execution to 30 seconds before its first DDL. Successful installation
also compares all six legacy readers' definitions, ACLs and owners byte-for-byte
against their catalog snapshot immediately before the migration.

Local verification: 7 migration lexical/provenance tests; all 454 Storefront
unit/contract tests on Node 24.22.2 plus TypeScript checking; 76 Flutter contract/readiness,
uncertain-save, binding and operation-ownership tests all passed. An initial
Storefront test attempt with host Node 22.14 failed before test execution because
that unsupported runtime lacks `registerHooks`; the required Node 24 run passed.
The broader suite initially detected CRLF in an unchanged pinned ETA fixture;
restoring that file to its exact existing Git blob bytes resolved the check.
No ETA source, fixture content or expected hash was changed.
The extended pgTAP tests cover absent/populated/explicit-null/cleared appearance,
legacy read-to-write preservation, media retraction, exact legacy/new projections,
private-helper ACLs, tenant/role scope and anonymous published read behavior.
Their execution, full DB suite, atomicity and real Auth/Storage/Flutter acceptance
remain final-candidate CI gates; these source checks are not a production PASS.
