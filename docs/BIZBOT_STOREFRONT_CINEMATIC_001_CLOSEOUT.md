# BIZBOT-STOREFRONT-CINEMATIC-001 — Preview closeout, 2026-11-03

Continue the existing isolated design branch. No main merge, Production
deployment, hosted migration, tenant setting mutation or payment changes.

## Status wording and source findings

The Home notice area is now a compact warm panel with short Arabic, Hebrew and
English copy. The closed notice says when **the restaurant** opens; it makes no
promise that ordering becomes enabled then. The paused notice keeps browsing
available. An open restaurant whose order admission is false shows neutral
"online ordering unavailable / menu browsing only" copy with no future promise.

The public `service.ordering_enabled` is **not a raw dashboard setting**.
`20261020143657_bizbot_platform_online_orders_353.sql` combines opening state,
pickup and the existing platform/pilot admission helpers. The adapter further
retains those admission checks. Neither was changed. Therefore closed/paused
admission must not produce a second message claiming settings were disabled.

A read-only hosted check found Maps' current `app.online_order_settings` switch
and channel submission switch both true, pickup true, profile paused false.
The obsolete `restaurant_storefront_profiles.ordering_enabled` remains false
and is **not** used as the configuration source. The Preview stays intentionally
browse-only and retains its captured closed state.

Limit: the current public API cannot distinguish a separately disabled setting
while the restaurant is also closed. The UI reports the known closed/paused
state without guessing that setting; the opening-time sentence promises only
restaurant opening. Exposing both independent reasons simultaneously would
require separately scoped public presentation metadata. No private settings
query or new order authority was added to the Storefront.

## Canonical name

Read-only hosted values: profile `display_name` and restaurant `name` both equal
`** خرائط البرجر **`; organization name is a different value, `برجر الخرائط`.
The canonical path remains profile `display_name` → adapter `tenant.displayName`
→ the shared `BrandLockup` in the header and footer. Stars are stored characters,
not introduced by the new design. Their author intent cannot be inferred.

The earlier Home-content contract explicitly preserves literal merchant names
and treats them as plain text, not Markdown. No alternative name was confirmed
during this followup. Stored values, accessible names and rendered canonical
names therefore remain unchanged; no guessed organization name or hardcoded
Maps name substitutes for the dashboard value.

## Appearance readiness

| Setting | Dashboard/save/read | Storefront application | Remaining |
| --- | --- | --- | --- |
| Background image | Existing media publisher and eligible-source selector → `hero_media_id` profile save → public `hero_url` | Hero, page backdrop, transparent navigation surroundings, footer | Publish the design reader; no new image migration. Existing upload/selection workflow, no new arbitrary-file upload. |
| Background/button HEX | Existing `primary_color` / `accent_color` controls, profile RPC, public read | Exact cinematic background/accent tokens | Publish the design reader. |
| Text/button-text HEX | New editor controls, strict six-digit HEX model, versioned content save/read and optional public appearance object implemented | Exact overrides on cinematic intro/menu | Compatible reader first, approved appearance migration, updated dashboard writer. Secondary Search/Flow/Request retain their existing color derivation. |
| Font | New Rubik/Alexandria/system selector, allowlisted serialization, content save/read implemented | Intro/menu and existing Search/Flow/Request font stacks | Same reader → migration → writer order. |

Read-only hosted metadata confirms the appearance column does not exist and
migration `20261102140930` is not applied. The Dashboard build script deliberately
disables `RESTOFLOW_STOREFRONT_EDITOR` in Preview; the menu Preview is not a live
dashboard editor demo. Existing cache/ISR refresh behavior remains unchanged.

## Focused evidence and limits

- Next live-mode production build and TypeScript pass; focused Home/appearance
  Node checks pass. No broad historical design review was repeated.
- Disposable PostgreSQL 17.5 via scratch-only PGlite 0.3.14 executed the unchanged
  appearance migration and real profile/content save/read functions, constraints,
  public-v4 appearance projection, idempotency and audit helpers: 18 checks pass.
  Two consecutive image/color/font saves, old-writer preservation, explicit reset,
  stale/invalid rejection and unchanged catalog/options/service were exercised.
- Those SQL-exported public envelopes are fed through the actual local live HTTP
  reader, decoder, adapter and browser ThemeScope. A test-only loopback transport
  replaces remote reads and supplies fixture image bytes; the application's
  origin guard and order admission code stay unchanged.
- The focused browser check covers all six open/closed/paused × wire-ordering
  combinations, canonical names in header/footer, RTL/no overflow, and both saved
  appearance profiles in computed CSS and background image URL selection.
- The SQL environment uses synthetic actor/rank, minimal core tables and a
  fixture older-v3 catalog projection. It does **not** verify full Supabase
  Auth/RLS, real media upload/download, or Flutter dashboard widget execution.
  Flutter/Dart and the full local Supabase stack are unavailable; those existing
  widget/pgTAP checks remain unrun. No hosted write was used to fill that gap.
- Full desktop and mobile captures visit every section and footer, decode all
  12 visible central/neighbor product images and two footer images, wait for fonts
  and paint, then capture from scroll top. Four categories and 20 products remain.
  No image-loading defect was reproduced; loading behavior was not modified.

Evidence files are in the task workspace `cinematic-evidence-v4`; the disposable
SQL report/exports/harness are in `appearance-sql-runtime`. No scratch runtime
dependency was added to the application or repository manifests.

## Publication

Update only `feat/BIZBOT-STOREFRONT-CINEMATIC-001-mobile-design`. A read-only
preflight found remote base `12fa178f309e57fe218bc352039222601cfab09b`, main
`be579180d43958f716872dac22daf24ba7cc8c26`, and no relevant overlap with Claude's
payment PR #370 or documentation-only PR #371. Merge and Production remain
separate owner approval steps.
