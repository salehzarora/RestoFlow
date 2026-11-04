# Cinematic v5 source reimplementation and portable delivery

Work ID: BIZBOT-STOREFRONT-CINEMATIC-001B. The owner approved this bounded
reimplementation after the original integration source could not be recovered.
The approved visual design is closed; this task adds no visual redesign.

## Provenance

Base: `a5c9c933856487f2f504aea59341650e154c502f`.
Branch: `fix/BIZBOT-STOREFRONT-CINEMATIC-001B-source-rebuild`.

The previously reported `4c14d48c35358158686de949e4fcc6c479363df6` is **not**
the identity of this work. Earlier checks already exhausted the reattached
worktree/object/reflog sources. This round searched only additional retained
Library sources: reports and images were available, not actual source archives,
bundles or patches. Personal Context retrieval was unavailable. No original
source bytes were recovered from a report's SHA references.

This implementation was independently written against the available base.
The delivery manifest records its actual commit, tree, bundle hash and import
result. No historical test result is attributed to the new commit.

## Bounded repairs

- Add independent background file selection/upload through the existing private
  `restaurant-logos` pipeline and editorial w960 publisher. The upload adapter
  never saves/removes the receipt-logo pointer or assigns a Hero. A verified live
  media row is selected into an unsaved appearance draft; the owner still saves.
  Dirty/readiness/permission/binding guards and publication retry ownership stay
  in the existing editor flow.
- Read `get_restaurant_storefront_content_v2` without a v1 fallback. The existing
  unapplied appearance migration installs this stable, invoker-only wrapper over
  the already authorized app getter. Missing migration stops the editor before
  uploads or writes; untouched legacy content remains valid on a ready backend.
- Require the staged media's exact source bucket/key/variant and explicit
  `source_mismatch = false` before public Storage or finalize. This applies to all
  media states and slots, closing the cross-source Hero repoint and concurrent
  retraction case. Existing editorial conflict and item error shapes remain.
- Move the unchanged Alexandria font and license next to their CSS consumer in
  `storefront/src/ui/storefront/fonts/`. The relative CSS URL contains no upward
  traversal and Next emits the bundled asset. No font bytes, visual rules,
  dependencies, public-asset allowlist or loading policy were changed.

Existing background/HEX/font/dimming settings, clear/fallback behavior, restaurant
name/status corrections, independent carousels, categories and cart/options
flows remain in the base implementation. No tenant content was hardcoded.

## Validation boundaries

The accompanying delivery report contains fresh command results and file hashes.
Meaningful local coverage includes the new uploader and readiness tests, the
publisher's duplicate/retry/race regressions, Storefront tests/typecheck/build,
and SQL execution in the available PGlite scratch harness. PGlite uses synthetic
actor and Storage metadata seams; publisher tests use real pinned codecs with
fake network services. Neither proves actual Auth/Storage authorization.

Actual Dashboard login, HTTP Storage upload/publication, two-user tenant
isolation, full Supabase pgTAP, hosted behavior and required GitHub CI remain
NOT_RUN. The prior environment failures were not retried. No Production data or
database, payment worktree, Git remote, PR or deployment was changed.

Payment PRs #370 and #371 were re-pinned before editing at
`54b19ab58ce72a2fa9a43860e31181a08222b254` and
`53d6a6adc38f308b7ed6b0dd62177e6edd5ad5ce`; their heads were unchanged. The delivery
check compares the actual rebuilt paths with their 34/1 changed paths.

## Reuse and remaining integration

The self-contained Git bundle is the source deliverable, not this report alone.
Import it into a new directory with `git clone --branch
fix/BIZBOT-STOREFRONT-CINEMATIC-001B-source-rebuild <bundle> <new-directory>`.
Compare `git rev-parse HEAD` and `git rev-parse HEAD^{tree}` with the delivery
manifest, then run `git fsck --full`. The delivery process performs this import
in an independent temporary repository before publishing the bundle to Library.

To run real integration, use a fresh authorized Docker-capable test host with
the full local Supabase stack (Auth, REST, Storage and Edge), CLI 2.107.0,
Postgres 17, Node 24 and Flutter 3.44.2. Create two synthetic restaurant owners
through genuine signup/onboarding, then test upload/publish/save/reload,
replacement, clear/fallback, 0/15/80 dimming, unchanged Hero/logo, duplicates and
cross-restaurant write/upload denials using their actual user sessions. Execute
the committed appearance/readiness pgTAP suites there. Use this new delivery
manifest for source pinning; the older runbook's `4c14d48` gate is obsolete for
this reimplementation.

Any later release still needs separate approvals and the safe order: compatible
readers actually serving routes/caches, approved migration, corrected publisher
verified in that environment, then the Dashboard writer/upload action. Clearing
the background does not make old strict readers compatible with new fields.
No push, PR, migration application or release is authorized by this delivery.
