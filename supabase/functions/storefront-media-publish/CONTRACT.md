# Storefront item-image publication — STOREFRONT-PUBLISH-002

This extends the Edge Function contract in [API_CONTRACT.md §4.44](../../../docs/API_CONTRACT.md#444-edge-function-storefront-media-publish-storefront-publish-001-proposed-decision-d-040).
It does not change the pinned `storefront-media-c4` recipe, codec pins, quality
ladder, byte limits, caller authentication, CORS, or logo/hero request shape.

## Item request

The existing eight identifier fields remain the exact request shape:
`request_id`, `organization_id`, `restaurant_id`, `slot`, `variant`,
`source_bucket`, `source_key`, and `rung`. An item request uses exactly
`slot: 'item'`, `variant: 'w480'`, and `source_bucket: 'menu-images'`.
The key must follow the existing organization/restaurant/branch-or-global/
`menu_item`/item/upload-UUID grammar. Private input remains capped at 5 MiB;
the output remains WebP within a 480-pixel box and 512 KiB. The request carries
no bytes, source-generation token, price, or profile assignment.

## Source freshness and association

After GoTrue authentication, exact request validation, and manager preflight,
the function calls `get_storefront_item_source(p_organization_id,
p_restaurant_id, p_source_key)` as the caller **before** downloading the private
original. Its manager-only success contains `source_snapshot` with exactly
`storage_object_id`, `storage_version` (string or null), and
`storage_updated_at`. The snapshot is passed unchanged as the item's optional
`p_source_snapshot` argument to `stage_storefront_media`; logo/hero calls omit
that argument. A client-supplied snapshot is an unknown request field.

The database proves the current live item's source path and storage generation
at stage, stage replay, finalize, and public item reading. The pre-download
snapshot closes the download-to-stage overwrite window. The snapshot is never
returned by this function or exposed by the public menu.

Item rows associate one source generation with its derivative. Different items
may have distinct media IDs sharing the same immutable content-addressed public
object, including bytes already used by a logo/hero. The function refuses an
item stage answer unless source bucket, key, and variant exactly match the
request and `source_mismatch` is false. Finalize must confirm that same media ID,
object key, and published state. Item publication never substitutes an existing
logo/hero association.

BIZBOT-STOREFRONT-CINEMATIC-001B also requires that exact source association for
logo/hero requests, before any public Storage operation or finalize, regardless
of the returned state. A legacy cross-source dedup answer returns the existing
`409 object_conflict`. Finalizing another source's row could republish it and
repoint its Hero, including when a live stage answer races with retraction.
Existing eligible media remains selectable through the Dashboard picker instead
of republishing identical bytes from another private key. Same-source recovery
and item error semantics remain unchanged.

## Outcomes and recovery

- `200 published` retains the existing envelope, describing the requested item
  association. The item is exposed through `storefront_menu.image_url`; no
  logo/hero profile pointer needs to be assigned.
- `404 source_not_found` means the source is missing, inaccessible, or no longer
  the current eligible item's image. This includes deletion or replacement
  between workflow steps and never becomes a cached success.
- `422 refused`, `code: 'source_stale'`, means the storage generation changed
  after the captured snapshot or since the staged association. Refresh the
  current item/source and start a new logical request; do not report publication.
- A refreshed generation changes the stage fingerprint. Reusing an already
  claimed request ID with that generation returns `409 restart_required` under
  the existing idempotency contract; use a new request ID from rung zero.
- Malformed or mismatched item success envelopes fail closed with
  `500 internal_error`; `uncertain` is false before stage and true after stage.

All existing uncertain-outcome retries, derived stage/finalize IDs, ladder
progression, content-address readback, and `x-upsert: false` behavior remain.
No overwrite, cancellation, retraction, or deletion is performed by this
function. An object uploaded before a later refusal can remain unreferenced;
an already uploaded public URL is not revoked by source freshness checks.

## Local proof

`test/validation.test.mjs` covers exact slot/bucket/variant combinations and
cross-scope keys. `test/handler.test.mjs` F39–F50 cover the item path, authorization,
snapshot origin/shape, lost-response recovery, source removal/replacement,
overwrite races, identical-byte association sharing, response identity, caps,
and new-generation restarts. Existing logo/hero, recipe, engine, license, and
static-guard suites remain regression checks. F36–F36c cover editorial duplicate
refusal in every state, a retraction race, and exact-source recovery. The service
double is not a database isolation proof; the migration's pgTAP tests verify
those invariants.

## Optional menu background companion

An authenticated restaurant-level manager can prepare one `bg2560` companion for an eligible published `w960` editorial image. The Dashboard sends exactly nine fields to this function.

```json
{
  "request_id": "<uuid>",
  "organization_id": "<uuid>",
  "restaurant_id": "<uuid>",
  "branch_id": "<uuid>",
  "base_media_id": "<published w960 media UUID>",
  "slot": "background",
  "variant": "bg2560",
  "base_rung": 0,
  "rung": 0
}
```

Both rungs must be integers from 0 through 4. After authenticating the caller and verifying management scope, the function obtains the private bucket, key, source generation, and recorded base dimensions and hash through `get_storefront_background_source_v1`. It validates the exact source scope before downloading the original with the caller JWT and existing bucket size limit.

The function derives c4 `w960` at `base_rung` directly from those bytes. A candidate proceeds only when the resulting dimensions and hash match the registered base. This comparison proves that the current source reproduces the base. The function releases that output before deriving the higher-resolution image from the same private bytes.

`storefront-background-b1` uses the existing pinned codecs, source limits, orientation, integer box reduction, metadata removal, WebP settings, quality ladder and 512 KiB output cap. Its larger resize uses fixed-point, pixel-centered bilinear sampling with premultiplied alpha and clamped edges. It fits inside 2560 × 2560, preserves aspect ratio, and never enlarges the original. Legacy `w480` and `w960` continue to use their c4 triangle resize.

The authenticated stage and finalize RPCs recheck the base, source generation and branch. The function verifies the returned association and complete immutable content address before storing the bytes and after finalization. The background namespace is the first 32 hex characters of SHA256 over UTF-8 `storefront-menu-background-v1:` followed by the canonical restaurant UUID. Its public key is `<namespace>/<content-sha256>.webp`. An existing object must match the derived bytes. Uploads use `x-upsert:false` and one-year caching. A retry reuses the request ID and stage/finalize keys. Background publication creates only the companion and leaves selection to the content editor.

- HTTP 200 with `{ok:true,status:"published",recipe:"storefront-background-b1",rung,media}` confirms a published companion. The media fields are `variant_id`, `base_media_id`, `object_key`, `content_hash`, `width`, `height`, `bytes`, `variant`, `recipe`, and `state`.
- HTTP 200 with `{ok:true,status:"not_needed"}` means the verified base already covers the available source detail.
- HTTP 202 with `{ok:false,status:"ladder_next",next_rung}` advances the high-resolution ladder by one rung.
- HTTP 422 with `{ok:false,status:"refused",code:"base_mismatch"}` means the supplied base rung did not reproduce the base. This occurs before any stage or public upload. For a legacy image with unknown rung, an explicit republish can try the next base rung. A confirmed matching rung stays fixed while the high ladder advances.
- Missing sources, stale generations, immutable conflicts, oversized output and uncertain runtime failures retain their existing typed outcomes. The editor can continue using the published base.
