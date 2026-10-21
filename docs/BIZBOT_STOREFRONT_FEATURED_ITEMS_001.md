# BIZBOT Storefront featured items

Work ID: `BIZBOT-STOREFRONT-FEATURED-ITEMS-001`, under Issue #360. This dedicated additive contract records the approved bounded local engineering choices before dependent implementation. The preceding contact/checkout slice is merged and deployed. No hosted migration, deployment, merchant-content edit, POS release or print action is authorized here.

## Merchant selection

An existing restaurant storefront profile owns `featured_item_ids uuid[] NOT NULL DEFAULT '{}'`. This is a set of **0–12 distinct non-null UUIDs**, stored in UUID order. Array elements must be one-dimensional, lower-bound one when nonempty. The set changes presentation only; product names, prices, modifiers, media, availability and ordinary catalog ordering retain their existing authority. It is independent of `popular` tags and makes no sales-ranking claim.

The manager reads the additive field through the existing profile read. A missing field on an old backend means the capability is unavailable; malformed present data is a decode failure. The generic profile patch allowlist and the three-field Home writer are unchanged.

The new public INVOKER wrapper and internal fixed-search-path DEFINER function are:

```text
set_restaurant_storefront_featured_items(
  p_client_request_id uuid, p_organization_id uuid, p_restaurant_id uuid,
  p_expected_version integer, p_patch jsonb)
```

The patch contains exactly one required key, `featured_item_ids`, holding the complete UUID-string array. UUID spellings may use upper/lower hex, but aliases of the same parsed UUID are duplicates and are rejected. Non-string, null, malformed, multidimensional, duplicate and oversized input fails closed. The raw JSON patch, scope and expected version bind the existing management request identity **before** normalization. Reusing an identity for a different raw payload conflicts.

Fresh manager authority is required before replay and after waiting for the existing restaurant/profile lock order. The writer never creates a profile. It uses the shared profile version CAS, existing request ledger and management audit; only selection and profile version change. Item and parent category must be active, nondeleted, in the exact organization/restaurant, and global or visible in the saved storefront branch. Sold-out products remain eligible: their existing public sold-out state stays authoritative. Missing/invalid branch or invalid selection is a refusal, never a partial filtered write.

## Public v3 boundary

`public.storefront_menu_v3(p_slug text)` is STABLE with fixed empty search path and the same public-read ACL as v2 (`anon`/`service_role`, not `authenticated`). It calls unchanged `storefront_menu_v2` exactly once, retaining its published hierarchy and single-statement snapshot, then adds exactly one top-level field:

```json
{"featured_item_ids": []}
```

The array is built on the **server from IDs already present in that same v2 `items` array**, in that array's order, intersected with the saved set. Hidden, inactive, deleted, foreign and branch-mismatched UUIDs must be absent from the serialized response itself. Sending private IDs and relying on an adapter to hide them is forbidden. A stale selection after catalog/branch changes remains private and does not expose or reactivate a product. Failure envelopes remain unchanged and contain no selection field.

A separate strict v3 decoder extracts the new field and delegates the remaining envelope to unchanged v2 decoding. It checks UUIDs, uniqueness, bound and subset membership. The live client uses v3 only; missing backend is an error, with no v2 retry/fallback. Explicit older fixtures may still adapt to all nonfeatured items. Existing cards render selected products once in canonical category/product order and use the established product-sheet trigger; no new card styles or dependencies are required.

## Dashboard source and save behavior

The new narrow catalog source uses the existing authenticated `MenuReadSource` over `list_menu`, loaded for the **saved profile storefront branch**, not the membership's possibly different branch. The management read includes inactive rows; existing `MenuSnapshot` helpers filter only tombstones. The source explicitly validates item/category tenant, branch, active state and parent linkage. Image-less products and distinct products sharing an image remain separate options. The existing image-only source catalog is unchanged.

`DashboardShell` wires the new source into the real editor seams. An unavailable catalog produces an honest error; no demo data substitutes. A dirty unsaved profile branch must be saved/reloaded before editing selections. Scope/profile changes discard stale catalog results. A selection save cannot race other local profile/Home/media saves.

The complete patch and request ID are frozen before awaiting a write. The new repository performs one POST, followed only by read-only reconciliation on an unknown result. Matching profile content alone cannot prove which request committed. The exact pending identity/body/version remains available for a deliberate retry, and unrelated writes remain blocked until reconciliation. No automatic POST retry is introduced. Fresh authorization still applies on replay.

New strings follow the existing shared AR/HE/EN ARB/generated convention, restricted to prefixed featured-control presentation strings. No shared business logic or locale authority changes.

## Verification and rollout

The authored required SQL suites cover manager/cashier/cross-tenant/revoked authority, raw idempotency, shared CAS and real races, array/type/alias/bound constraints, parent/item scope, unchanged v1/v2/generic/Home3 definitions, and a **raw serialized v3 DTO negative test** for stale/foreign/deleted/branch-mismatched IDs. Their actual ephemeral CI execution is required and pending; source inspection is not SQL execution proof. Local Dashboard tests cover complete source, saved-branch real wiring, uncertainty and stale results; Storefront tests cover strict v3, no fallback and unchanged canonical data. Focused browser verification exercises the existing card/sheet behavior in AR/HE/EN with a nonempty synthetic v3 menu.

Local SQL integration is NOT RUN: the cached PostgreSQL image alone does not provide a verified current Auth/Storage/Realtime bootstrap. Fixture preparation stopped before database startup or SQL execution; existing fixtures remain untouched. The complete migration, RLS/unit and genuine concurrent-session suites must pass in the existing GitHub Actions ephemeral Supabase 2.107.0 environment, which supplies the real service bootstrap. No guessed schemas, old schema dumps, atomic/C# application runner or production database client is used. Local Node/Flutter results remain separate from actual SQL CI evidence.

Later production rollout requires separate exact-head merge/security approval and exact-version hosted migration. Deploy backend v3/writer before Dashboard/Storefront consumers. Owner selection/save plus public read/render verification remains required; no order or print test is needed for this feature. No deployment or physical success is claimed by local tests.

Preserve existing Home copy/public phone, live ordering/notifications/Cron, protected 625 holds and BLOCKED revision 1264. No ETA/receipt-phone/POS/APK/payment or printer work belongs to this slice. The separately prepared ETA contract remains review-only; v69 is not build-authorized. Preserve the original design handoff, previous evidence and the prior mock-harness incident's UNKNOWN connection outcome.
