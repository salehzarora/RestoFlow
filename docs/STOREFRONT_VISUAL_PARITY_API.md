# Storefront visual parity contract

Work ID: `BIZBOT-STOREFRONT-VISUAL-PARITY-001-API`. This is the narrow compatibility extension explicitly authorized by the owner's visual parity request, tracked in the execution packet. It adds no order, payment, POS, device or printing authority. The visual review phase permits isolated integration only; applying hosted SQL and deploying Production remain outside scope.

## Scene selection

The optional `appearance.scene_preset` is exactly `null | "reference_dark"`. Absence preserves existing stored selection on partial/legacy writes; explicit JSON null restores the legacy presentation. Neither selection nor clearing rewrites the primary, accent, text, button-text, font or background fields. Existing required nullable full-HEX fields `text_color` and `button_text_color` retain their contract. Menu background dim remains an optional nullable integer from 0 through 80; presentation defaults to 15 and preserves zero.

`public.get_restaurant_storefront_content_v3(uuid, uuid)` and its scoped `app` body return the existing content envelope with this optional field. The existing `public.set_restaurant_storefront_content_v1` validates and merges the field using the existing branch/version checks, idempotency identity, tenant authority, media-use checks and audit. Its response shape is unchanged. Audit old/new documents retain the scene selector.

Both public and app `get_restaurant_storefront_content_v2` strip only `document.appearance.scene_preset`; v1 continues to omit appearance. Public `storefront_menu_v5` strips only `content_v1.appearance.scene_preset` and keeps legacy item image identities. Earlier readers are unchanged. Strict older clients therefore continue to accept their own response versions after a new editor saves a scene. New clients require their new read endpoint and do not downgrade on failure.

## Public product variants

`public.storefront_menu_v6(text)` retains the existing slug-only public read authority and failure envelopes. It adds scene selection plus a bounded `product_images_v1` array produced by `app.storefront_product_images_v1(organization, restaurant, branch)`. That internal helper must return only current, served, authorized product selections, never arbitrary original keys or unregistered URLs.

Each array row has exactly these fields:

| Field | Value |
| --- | --- |
| `item_id` | Unique served item UUID |
| `w480_url`, `w960_url` | Existing canonical public content-addressed `.webp` paths |
| `width480`, `height480` | Positive integers, each at most 480 |
| `width960`, `height960` | Positive integers, each at most 960 and no smaller than the corresponding 480 dimension |

There are at most 500 rows, no duplicate item IDs and no private source identifiers. The v6 reader substitutes a selected row's `w480_url` into that item's `image_url`. The decoder requires that equality. The original legacy item media remain visible to v1–v5 readers. Sources smaller than a variant limit are not required to upscale. The adapter provides absolute responsive variants and deduplicates equal width descriptors without changing item prices, modifier groups, order eligibility or other catalog fields.

The v6 decoder also accepts absence of this optional array for legacy/default documents; old decoders reject the extension. Unknown appearance fields, malformed scene tokens, arbitrary image URLs, unknown or duplicate item references and invalid dimensions reject the whole response. The deployed recipe remains `storefront-media-c4`, with unchanged 480/960 variant limits and immutable URLs.

## Private product publication

Work ID `BIZBOT-STOREFRONT-VISUAL-PARITY-001-MEDIA` adds six versioned public
invoker wrappers over scoped app definers. Only real authenticated managers or
owners covering the organization and restaurant may call them; anonymous users,
devices without that authority and `service_role` have no grant. Every operation
requires explicit organization/restaurant IDs. Private originals remain in
`menu-images`; `menu_items.image_path`, receipt/logo and editorial Hero pointers
are not changed by product selection.

| RPC | Additional input and successful result |
| --- | --- |
| `get_storefront_product_original_v1` | Item ID → current private source key, Storage snapshot, selection version and selected derivative ID (nullable). |
| `register_storefront_product_derivative_v1` | Request ID, item ID, original key/snapshot, candidate key, `original`/`cutout` treatment, expected selection version → derivative ID and candidate key. |
| `get_storefront_product_source_v1` | Derivative ID → registered candidate key and Storage snapshot after both source generations are proved current. |
| `stage_storefront_product_media_v1` | Request ID, derivative ID, candidate key/snapshot, variant, SHA-256, width/height/bytes → registered media identity and state. |
| `finalize_storefront_product_media_v1` | Request ID and media ID → published identity only after the current source pair and actual Storage object metadata are verified. |
| `select_storefront_product_derivative_v1` | Request ID and derivative ID → atomically selected derivative and next selection version, only with both current published variants. |

A source snapshot contains exactly Storage object ID, version (nullable) and
updated timestamp. Candidate scope must match the original's organization,
restaurant, branch and item. `original` uses the original key; `cutout` uses a
different private PNG. Source generations are rechecked before private download,
stage, finalize, selection and public read. A same-key overwrite invalidates the
old candidate. The Dashboard also compares source snapshot and exact original
bytes when refreshing its proof; a selection-version-only advance can retain a
candidate, an original change cannot.

Writes use the existing actor/request operation ledger and restaurant lock.
Typed failures do not consume a successful identity. Retries keep the same ID
and payload; a replay cannot revive a replaced selection. Only the final select
call changes the active presentation, so failure while publishing the second
variant leaves the previous pair intact. Unknown network/commit outcomes remain
uncertain until authoritative readback; they are not reported as success.

The existing Edge function accepts one new exact request shape: `slot: "product"`
with all existing fields plus `product_derivative_id`; both `w480` and `w960` are
allowed from `menu-images`. It reads the registered candidate as the caller and
derives each size directly with unchanged c4. Old slots retain their exact key
sets. Product finalization never repoints another source's Hero. Separate row
associations may share identical content-addressed bytes, but bytes are compared
on retry and never overwritten. The legacy media picker/profile/editorial writer
exclude product associations; authoritative media-use checks protect selected
product pairs from retraction.

## Rollout and verification

The product registration/helper migration must precede `20261104155000_bizbot_storefront_visual_parity_scene.sql`. That migration must precede clients using content v3/menu v6. New private read grants remain `authenticated` only, with the same scoped manager/owner checks; the new public menu grant remains `anon`/`service_role`, and private helpers receive no anonymous authority.

Focused tests cover strict old/new decoders, null/omission semantics, current-product binding, bounds, unchanged order fields, Dashboard readiness and model rejection. Rollback-only pgTAP covers authoritative save/readback, replay, legacy write preservation, exact legacy projections, audit contents, database validation and tenant/role denial. Full real-service media integration and the consolidated independent review remain delivery gates.
