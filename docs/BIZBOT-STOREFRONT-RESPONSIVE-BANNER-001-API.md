# BIZBOT responsive menu banner — local API contract

Work ID: `BIZBOT-STOREFRONT-DESKTOP-BANNER-FIT-001`

This is a local candidate contract. It does not authorize hosted SQL, a deployment,
a merchant setting change, or publication of merchant originals. It adds one
migration, no table, no Edge function, no Storage policy and no new media recipe.

## Optional appearance data

The existing content writer remains `set_restaurant_storefront_content_v1`.
The current branch, authority, request fingerprint/replay, compare-and-swap,
content-only save and audit path remain the same.

| Stored key | Accepted value |
| --- | --- |
| `menu_banner_layout` | `"responsive"` or null |
| `menu_banner_desktop_media_id` | eligible published editorial w960 UUID or null |
| `menu_banner_mobile_height_px` | integer 320–640 or null (auto) |
| `menu_banner_desktop_height_px` | integer 240–560 or null (auto) |
| `menu_banner_desktop_focal_x` | integer 0–100 or null (50) |
| `menu_banner_desktop_focal_y` | integer 0–100 or null (50) |

Missing/null layout retains legacy rendering; no restaurant is opted in by the
migration. Missing optional keys preserve stored values when an old editor
saves. Explicit JSON null clears only that key. Clearing layout retains the
independent desktop image, heights and focal values. The phone image, its
existing focal values, menu background and welcome image retain their meanings.

Renderer auto heights are phone natural ratio clamped to 320–640 px and desktop
natural ratio clamped to 240–480 px. Explicit desktop height permits 240–560 px.
These are presentation rules, not an inference that mobile and desktop share a
source image or a crop. No new raw or private image URL is sent to the browser.

## Read versions and old clients

* Management: `public.get_restaurant_storefront_content_v6(uuid,uuid)`, using
  `app.get_restaurant_storefront_content_v6(uuid,uuid)` for the existing management
  authentication/rank/ancestry/current-branch checks. The public wrapper is an
  invoker. Only authenticated has EXECUTE on both new management functions.
* Public: `public.storefront_menu_v11(text)` calls admitted v10 and preserves its
  product-original manifest, catalog, availability and failure envelopes.
  EXECUTE is granted only to anon and authenticated, not service_role/PUBLIC.
* New functions are owned by postgres and use an empty search_path.
* Old management v1–v5 and public menu v1–v10 do not gain unknown fields. The common
  old content reader removes the six new stored fields. v6 appends them only after
  its existing v5 scope checks. Old function definitions are otherwise retained.
* Content writes audit old/new documents through v6 so a new presentation change
  is visible rather than omitted from the audit. Existing audit/replay/locking
  semantics are retained.

v11 appearance uses `menu_banner_desktop_url` in place of the private desktop ID.
It also includes `menu_banner_width`, `menu_banner_height`,
`menu_banner_desktop_width`, `menu_banner_desktop_height`: integer base-derivative
pixel dimensions, or null. Each pair comes from the same eligible w960 row as the
URL it describes. The four dimensions are not the high companion dimensions.
The stored six keys and these public fields are an explicit new decoder version;
strict old decoders must keep calling their old RPCs.

A missing/unpublished/ineligible desktop reference returns a null public desktop
URL/dimensions and a scoped management v6 warning. No raw Storage path, source
snapshot, private source ID or key is emitted. Existing editorial admission
checks bind org, restaurant and allowed source branch and require published w960,
public WebP metadata/size, and existence of the private scoped source. A retained
reference is protected by the existing media-in-use guard even with layout off.
The existing same-source repoint operation also repoints the desktop reference;
clearing/replacing it does not clear phone/background/welcome assignments.

## Desktop higher-resolution reuse

`w1920` is not a supported generic editorial variant and is not introduced here.
The base stored ID remains the existing w960 row. The existing background
publication pipeline may additionally produce its existing `bg2560` companion,
using `slot="background"` as the publication recipe; assigning that base as a
banner does not assign it as the menu background.

v11 may add top-level `menu_banner_desktop_images_v1`, with the exact public shape
already used for the v7 menu-background manifest:

```json
{"base_url":"/storage/v1/object/public/storefront-media/...webp","variants":[
  {"url":"/storage/v1/object/public/storefront-media/...webp","width":960,"height":320},
  {"url":"/storage/v1/object/public/storefront-media/...webp","width":2560,"height":853}
]}
```

Those numbers are illustrative, not a claim that every image has these sizes.
The inline query reuses the existing current-context admission: same org,
restaurant, current branch and selected base; published companion; matching base
hash; matching private source generation snapshot; public high object WebP/size
metadata. It does not alter v7. The client must bind `base_url` to the desktop URL
and validate the pair before creating native srcset candidates. Integer resize
rounding may slightly vary the raster aspect; no identical-pixel claim is made.
A base with no valid current companion stays a valid w960 fallback, with a
possible sharpness limit at wide desktop sizes. No image processing occurs on a
menu/details read and no new helper is exposed for source access.

## Local tests and staged integration

`supabase/tests/storefront_responsive_banner_001_test.sql` contains rollback-only
synthetic tests for validation, boundaries, omission/null, independent device
settings, real shared writer CAS/replay, branch/tenant scope, old reader surfaces,
paired dimensions, current companion association/generation, media-in-use and
same-source repoint, clear/unpublish fallback, audit, role revocation and ACL.
Synthetic Storage metadata proves SQL associations/authorization, not uploaded
image bytes or an Edge E2E receipt. Docker is unavailable in this local phase;
these pgTAP cases must run in the existing isolated integration services.

The new contract must have its own post-v10 migration stage before v6/v11 UI
consumers run. Existing historical #379 evidence and strict rejection of unknown
successors remain intact. The existing v9/v10-only coordination approvals do not
authorize these new reserved edits automatically:

* `supabase/tests/support/cinematic_001b_migration_contract.mjs`
* `supabase/tests/support/run_cinematic_001b_migration_atomicity.mjs`
* `supabase/tests/support/cinematic_001b_migration_wrapper.test.mjs`
* The six exact public-surface security baseline tests for device session,
  order edit, ACL remediation, storefront read/publish and SEO discovery.

A separate reviewable proposal is required for the new raw migration pin,
management v6/public v11 phase and literal new public surface. Never accept an
unknown successor or relax negative equality tests. The existing CI temporary
services and real media publisher remain the integration route; no new lab or
MCP connection is needed. Hosted ordering is existing contracts → this migration
and independent verification → protected UI release, under later authorization.

Owner coordination update: the exact nine-file guard proposal at SHA-256 `2c6283d1c4d8449c81437b9176e5fc0f5cc41a776e9cdcda4cf5b23236224fdc` was approved and applied locally in this round. Earlier proposal wording below/above remains preparation history; no hosted or payment-guard deployment is authorized.
