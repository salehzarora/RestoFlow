# Storefront item-image publication — STOREFRONT-PUBLISH-002

This extends the Edge Function contract in [API_CONTRACT.md §4.44](../../../docs/API_CONTRACT.md#444-edge-function-storefront-media-publish-storefront-publish-001-proposed-decision-d-040).
It does not change the pinned `storefront-media-c4` recipe, codec pins, quality
ladder, byte limits, caller authentication, CORS, or logo/hero request behavior.

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
object key, and published state. Legacy logo/hero source-mismatch behavior is
unchanged; item publication never substitutes an existing logo/hero association.

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
- Malformed or mismatched upstream success envelopes fail closed with
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
static-guard suites remain regression checks. The service double is not a
database isolation proof; the migration's pgTAP tests verify those invariants.
