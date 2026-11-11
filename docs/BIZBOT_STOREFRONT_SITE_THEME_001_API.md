# BIZBOT-STOREFRONT-SITE-THEME-001-API

Local implementation candidate. No hosted migration, deployment or merchant opt-in has been performed.

The optional branch-content key `appearance.site_theme` accepts only `light`, `dark` or explicit JSON `null`. Omission and `null` retain legacy presentation; historical `visual_preset`, scene, brand colors, text colors, font, selected media and dim are not rewritten. The public VM exposes the optional value as `Tenant.siteTheme`. A stored profile `visual_preset: light` is not itself an opt-in to the new white journey.

## Versioned boundaries

- `public.storefront_menu_v8(text)` adds only optional `content_v1.appearance.site_theme` to the existing v7 response. It first uses v7's published, active, same-tenant admission and image contracts. The selected content row is joined using organization, restaurant and the profile's saved Storefront branch. Unknown/unpublished tenants keep the existing failure envelope.
- `public.get_restaurant_storefront_content_v4(uuid, uuid)` and its authenticated `app` helper return the same management envelope as v3, with the optional document field. Existing actor identity, ancestry and rank checks are copied unchanged. Execution is revoked from PUBLIC/anon/service_role and granted to authenticated, matching the existing management authority model.
- Management v1..v3 and public v1..v7 retain their strict shapes. v3 projects out the new key; v2 continues to remove scene too. Public v5/v6 project out the new key, so v7's existing delegation and image manifest remain intact. Earlier readers do not consume appearance.
- Current clients read v8 first. Only an exact documented missing-v8 HTTP404 permits v7; only an exact missing-v7 HTTP404 then permits v6. Credentials, slug, body and the original five-second signal remain identical across attempts. Invalid/malformed successes, denied responses and arbitrary HTTP/transport errors never downgrade or use fixtures.
- All decoders remain closed. The v8 decoder validates and removes only its own optional key before using the unchanged strict v7 decoder, then restores the validated enum. The v7 and older decoders still reject that key even when its value is null.

## Writes and compatibility

The existing `set_restaurant_storefront_content_v1` RPC, parameters, response, operation identity, request fingerprint, replay, profile version CAS, expected saved branch, ACL/rank checks, media validation and optional-key merge are unchanged. The validator/table constraint add the bounded enum. The writer's only body changes are the two old/new audit-document reads from v3 to v4; otherwise a strict old reader would erase the new field from audit evidence.

The Content Save action owns the setting, within the current saved branch's appearance draft. Profile Save continues to own profile colors and `visual_preset` independently. An old editor omitting the new key (or omitting appearance entirely) preserves the stored value through the current merge. Explicit null is a deliberate reset, not a guessed default or an automatic conversion. Existing conflict/uncertain replay/readback behavior is retained. A new editor uses v4 without treating an older server as write-capable.

## Deployment order for later approval

This file is a local contract implementation, not authorization to publish it. A future release must install the additive compatibility migration first with no opt-in writes, verify legacy/current readers, then deploy the renderer and new editor, and only then expose an explicit merchant save. No opt-in is backfilled. No historical migration or payment guard is changed. Migration ordering/baseline coordination with Claude is required before a hosted apply; this task does not alter the shared migration harness or CI/config/lockfiles.

The schema migration is `20261110150043_bizbot_storefront_site_theme_001.sql`, created using the already installed Supabase CLI2.107.0. It changes the existing JSON check/validator, versioned management/public projections, and the two complete-audit reads in the existing writer. It adds no table/column/job/service, requests no image processing and performs no catalogue or merchant-data updates. Lock timeout5s and statement timeout30s bound a future apply attempt.

## Focused local evidence

Evidence is outside Git in `release-evidence/STOREFRONT-MOBILE-ORDERING-UX-002-IMPLEMENT-20261110/api-local-tests/`.

The test database is the NEW `ux002_site_theme_20261110` in the already isolated `supabase_db_BIZBOTHomeIsolatedLive001` container. Only schema, never data, was copied from the synthetic `supabase_db_VISUALPARITY001` stack. That source has scene/adminv3/product-image helpers but no v7. Its migration history ends earlier than some manually installed helper definitions; it is a bounded dependency baseline, not a claim that full main was applied. The existing main background-v7 dependency was applied only to the new database, followed by the candidate once. Required synthetic storage buckets are the only persistent fixture rows; contract test fixtures roll back. Existing databases/containers are untouched and no database was dropped.

The first schema-only restore used `--no-owner` and stopped at a restricted realtime function parameter. An observed-boundary resume as the existing local superuser rolled back on event-trigger ownership. The final schema-only dump retained original owners; `--clean --if-exists` was restricted to the incomplete NEW database and restored transactionally. No database-level CREATE/DROP statement was accepted. Logs and both source dump hashes are preserved. These are local setup failures, not test regressions or production operations.

- Before the candidate, the new SQL test records missing v8/v4 boundaries and fails on the missing v8 read; no fixture transaction commits.
- The new rollback-only SQL suite passes54 assertions: strict enum/null/unknown keys, no implicit creation, old public/admin projections, selected media/dim/scene/colors/font retention, old-editor omission, replay, stale CAS, branch conflict, full audit, rank/tenant/ancestry checks, anonymous management denial and unpublished admission.
- Existing scene/content-contract/background-clarity SQL suites pass on the same isolated dependency baseline. These are focused compatibility executions, not a full-main or hosted suite.
- Node24.22.1 runs94 focused tests covering v8 plus existing strict content/scene/background/live/featured/home/source rules. Ambient Node22 was initially unsuitable for the existing `registerHooks` harness. An intermediate Node24 run exposed stale endpoint expectations and the new synthetic test's unsupported origin; endpoint assertions were updated to v8 and all network reads remain stubbed. No origin guard was weakened.
- Existing browser/offline harness endpoint allowlists now target exactly v8 rather than v7; no host/auth/body/verb restriction is broadened. These harnesses still need the root task's combined app/browser checks. This API-only work does not claim visual acceptance, actual Dashboard persistence, payment coverage or deployed behavior.

Security guidance was checked against the current [database functions documentation](https://supabase.com/docs/guides/database/functions) and changelog on10 November2026. Existing invoker/definer choices, qualified names/empty search paths and restricted execution grants are preserved. Hosted advisors were not invoked; local catalog/role and tenant-boundary assertions exercise the changed functions without production access.
