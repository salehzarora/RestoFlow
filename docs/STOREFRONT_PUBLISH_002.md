# STOREFRONT-PUBLISH-002 — existing product images

This work extends the existing publisher; it does not publish any hosted image,
apply a hosted migration, or deploy an Edge Function. Ordering and delivery stay
disabled. Products, prices, POS, KDS, printing and Storefront design are unchanged.

## Workflow

Dashboard Settings → Storefront → Product images offers **Publish / refresh all**
and a per-product **Publish / refresh** action. It reloads existing private
originals before starting, processes them sequentially, and reports each result.
No original is manually uploaded again. Authentication or service failure stops
the batch; an individual missing/refused image does not block the others. Unknown
outcomes retain the request identity for retry. Switching editor scope stops the
remaining batch; an already submitted request may still finish in its original,
server-authorized scope. Product publication never writes a profile media slot.

The new workflow has Arabic, Hebrew and English copy. Existing logo/hero controls
retain their behavior and do not offer product derivatives as profile media.
The existing bounded media list remains dedicated to logo/hero history: item
generations are excluded before its 200-row limit, so bulk publication cannot
crowd existing profile media out of their management controls.

## Contract and safety

- The caller sends the existing eight-key function body with `slot: item`,
  `variant: w480`, and `source_bucket: menu-images`.
- The function uses the signed-in caller's JWT throughout. No service-role key,
  anonymous publication, private URL exposure, or public-original upload is added.
- Before downloading, a manager-scoped source read captures the current private
  object's generation. Staging compares that snapshot; finalization and the public
  reader recheck it. A replaced/deleted source or changed product association
  cannot authorize a stale derivative. No source snapshot enters the public menu.
- The existing bounded WebP recipe, content-hash object key, no-overwrite upload,
  readback, staged lifecycle and request ledger are reused. Separate item
  associations can share identical derivative bytes without rebinding another
  product or changing the legacy logo/hero deduplication behavior.
- The existing public reader resolves current published `menu-images/w480`
  associations to opaque public WebP URLs; original paths remain private.
- Retraction/removal prevents association in fresh menu reads. Existing CDN copies
  are not recalled. The current Storefront page uses its existing 60-second ISR
  revalidation policy; already cached/rendered pages can retain an older document
  until successful revalidation/reload. This work does not add a cache purge service.

See the function's [contract](../supabase/functions/storefront-media-publish/CONTRACT.md)
and the migration/tests in this PR for the precise source-generation and replay
rules. The public `storefront_menu` response shape remains unchanged.

## Separately authorized hosted release

After implementation review and a separate owner authorization:

1. Apply this PR's publication migration through the normal migration
   process. Existing logo/hero callers remain compatible.
2. Deploy the updated `storefront-media-publish` function with its unchanged pinned
   codecs, configuration and JWT verification. Do not change secrets or buckets.
3. Use the Dashboard workflow as an authorized Maps Burger manager to publish the
   20 eligible existing originals. No product, price, ordering or delivery changes.
4. Check that fresh public menu responses contain 20 opaque public derivative URLs,
   that the images render after normal revalidation, and that private URLs and
   credentials are absent. Recheck the existing logo/hero and browse-only state.

The hosted steps above are **not executed by this implementation PR**. Merging the
code alone is not production acceptance. Before the migration/function release,
an old function refuses the new item slot; the Dashboard reports failure rather
than claiming publication. If the new function meets an old schema, publication
fails closed before the item upload. Do not reverse the hosted release sequence.

## Design-source clarification (read only)

The September 20 `Mobile app design project/BIZBOT_STOREFRONT_DESIGN_HANDOFF`
is the 11-screen design implemented by PR #285 (merged September 23). That PR's
accepted head is an ancestor of this work's baseline. Its Storefront UI CSS,
theme tree and public assets are unchanged at the baseline.

The October 13 download `C:/Users/saleh/Downloads/Mobile app design project.zip`
and its extracted handoff contain the same 61 files, all SHA-256 identical to the
repository handoff. They are a repackaging, not a newer design. No genuinely newer
approved package was found in the bounded Downloads/Desktop/Claude-output search.
Read-only production HTTP checks found all 164 current-main home/menu CSS classes
and matching geometry/tokens; the served Arabic/Latin fonts and BIZBOT symbol are
byte-identical to baseline `cf5f5018`. Together with PR ancestry and the launch
deployment record, this corroborates that the September design is already live;
HTTP responses alone do not expose the deployment's Git identity.
The correct newer Claude Design package or exact artifact reference is needed
before STOREFRONT-DESIGN-002. No design implementation is included here.
