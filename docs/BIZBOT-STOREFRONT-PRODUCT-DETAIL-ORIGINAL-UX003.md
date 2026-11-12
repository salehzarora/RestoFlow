# UX003 — scene fade and separately published detail Original

Work ID: `BIZBOT-STOREFRONT-BRAND-HERO-UX-003`.
Local candidate only. No hosted migration, deployment, merchant write or image backfill.

## Presentation

The existing full-width top banner fades over its last40% into the independent
menu scene. The opaque top-scene background and old tinted overlay are removed;
the banner layer alone is masked. Geometry, readable control surfaces, transparent
sticky categories, scene selection, dimming and light/dark values are retained.

## Missing reference and minimal extension

The existing v9 response exposes the selected product image pair only. It cannot
identify an independently published Original after a cutout becomes selected.

New migration: `20261112011934_bizbot_storefront_product_detail_original_001.sql`.
It adds private `app.storefront_product_original_images_v1(uuid,uuid,uuid,uuid[])`
and public `public.storefront_menu_v10(text)`. No table, RLS, bucket, recipe or
existing function is changed. v10 first performs v9 admission and appends the
optional `product_original_images_v1` manifest containing exact rows:

```json
{"item_id":"UUID from the served catalogue","url":"immutable public WebP path","width":960,"height":640}
```

Eligibility requires the same active item/category/org/restaurant/branch and
already-admitted item IDs; a current-generation Original registration; candidate
key equal to original key; a published, not-unpublished w960 file; a matching
public Storage WebP object/size; an exact restaurant/hash path; dimensions1..960
and bytes1..524288. One deterministic newest valid publication is returned per
item. Selection revision alone does not invalidate that Original. Changing the
private source generation does. No private source key or signed URL is returned.

Both new functions have empty search_path and revoke default PUBLIC execution.
Only v10 grants anon/authenticated execution. The helper is private. Existing
v5–v9 definitions, grants, payloads and selected image projection remain intact.
The strict client negotiates v10→v9→v8→v7→v6 only on each exact missing requested
RPC, sharing the original5s deadline/body/public credentials. Invalid payloads,
authorization errors or other failures never trigger a permissive downgrade.

## Explicit publication, never selection

Dashboard: open the existing product media editor, load Original normally, then
choose **Publish Original for details / نشر الأصل للتفاصيل**. This explicit action
registers treatment=original against the current snapshot/selection CAS, invokes
the existing caller-authorized c4 publisher for w960 only and reads back the
source/selection proof. It never invokes select, uploads a replacement source,
runs segmentation or changes the saved menu photo choice. Unconfirmed transport
results retain the same request identity for reconciliation; source/selection
changes are reported without restoring an earlier selection. Ordinary upload
and the existing Original/cutout selection action retain their behavior.

ProductSheet mounts DetailImage only when opened. It tries detailImage, then the
selected image, then the existing placeholder, once per distinct failed URL.
The resource-identity key isolates late errors from a changed item. Image fitting
is contain inside the existing reserved themed frame; the slider, listing, cart,
options, quantity, prices, validation and submit logic are unchanged. No original
image catalogue is downloaded in advance. Public immutable files use normal caching.

## Evidence and actual acceptance boundary

Focused local evidence is outside Git in
`release-evidence/UX003-SCENE-DETAIL-20261112/`.
SQL54/54 (one rolled-back transaction with synthetic fixtures/real PostgreSQL
roles), Dart101/101, contract63/63 and five real-React component cases passed.
The browser component test supplies synthetic image bytes and proves only
loading/fallback behavior. Actual app screenshots currently prove selected-image
fallback with contain on phone/desktop, not dashboard-origin publication.

**Original in details: NOT ACCEPTED. Real Edge publication: NOT_RUN_UPLOAD_E2E.**
The existing local Home Edge mount points to a missing source/config and is
stopped; the other historical stack is also stopped and not host-routed. No new
runtime, proxy publisher, lab or CI impersonation was created. The existing
PR-only `cinematic-integration` route needs its explicit reviewed migration
pins/phases extended through v9/v10 and a Dashboard Original→Edge→Storage→v10→
same-product detail lifecycle before real publication acceptance. Those reserved
workflow/guard files were not edited in this local-only task.

The three inherited source assertions remain failing (LiveCartDock media helper,
fixed module order and its negative control). Actual live menu JS remains above
its690000raw cap:698891bytes = inherited698440 + new451. CSS menu13983Br and
search13288Br are below14000. Official default-fixture output checks31/31 pass;
that separate lane does not waive the live JavaScript failure. No cap is raised.

## Future compatible sequence; not authorized execution

1. Coordinate the new migration identity/history and explicit test pins with
   Claude/payment owners; do not edit their frozen baselines from Storefront.
2. Extend/run the existing authorized integration lifecycle on the final source;
   prove actual original/selected bytes, independent selection, replacement and
   source invalidation, tenant isolation and fallback. Do not silently backfill.
3. Resolve size/source-test gates in their agreed scope. Full required CI and
   hosted SQL/API review/application remain later release gates.
4. Apply the reviewed additive contract before deploying clients, through the
   official authorized route. Reuse the existing c4 publisher unchanged. Publish
   product Original details only by an explicit merchant action. No paid service,
   automatic merchant setting change, payment work or catalogue-wide processing.
