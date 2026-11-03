# BIZBOT-STOREFRONT-CINEMATIC-001B — Appearance controls

## Scope

Approved companion to BIZBOT-STOREFRONT-CINEMATIC-001. Branch:
`feat/BIZBOT-STOREFRONT-CINEMATIC-001B-controls`.

The existing hero image becomes the page background, including behind the
transparent navigation and footer. The dashboard retains its existing media
publisher, source selection, slot assignment and profile version checks.
There is no additional upload endpoint or storage bucket. Images are selected
from the existing eligible menu/restaurant image sources.

Primary/background and accent/button colors still use the existing
`primary_color` and `accent_color` profile fields. Two optional text overrides
are added to the existing content editor, with English, Arabic and Hebrew copy.
The final design refinement also adds an optional font choice using the same
appearance object: Rubik (existing default), Alexandria (self-hosted Arabic
variable font already licensed in `site`), or the visitor's device font.
The controls accept six-digit HEX values, show a swatch, and restore the design
default when left blank. Existing warnings now ask the editor to check contrast
without claiming the storefront will replace their selected color.

## Contract extension

The private content document and public `content_v1` may contain:

```json
{
  "appearance": {
    "text_color": "#fff4e6",
    "button_text_color": "#14120f",
    "font_family": "alexandria"
  }
}
```

- `appearance` is optional. Its two color keys remain required, with optional
  `font_family`. Unknown keys, a null object, and missing color keys fail.
- Each color value is either null or exactly `#` plus six hexadecimal digits.
  Uppercase input is accepted and normalized to lowercase. Named colors,
  shorthand, alpha channels, whitespace and CSS expressions fail.
- A null value means use the storefront default for that color.
- `font_family` is null or exactly `rubik`, `alexandria`, or `system`. Null
  restores the existing Rubik default. Omission keeps the legacy document
  shape; an older color-only save preserves any active stored font choice.
- Documents without `appearance` keep their previous shape. Existing content
  saves that omit it preserve the active stored overrides; they do not restore
  old values from a tombstoned content row.
- Invalid appearance input uses the existing `presentation_invalid` reason
  with `appearance`, `appearance.text_color`, or
  `appearance.button_text_color` as the field.
- RPC signatures, profile version increments, branch binding, idempotent retry,
  existing audit action and authorization checks remain unchanged.

Persistence is one nullable `appearance jsonb` column on the existing private
`app.storefront_content_profiles` table. A CHECK constraint restricts stored
values to the exact normalized shape. The existing content shape/read/save
functions and public v4 content projection include the optional field.
No new endpoint, grants, RLS policy, authentication, order or payment behavior
is introduced. Shared localization packages are untouched.

The font refinement also maps the safe enum to a fixed CSS font stack in both
cinematic and existing secondary surfaces. Alexandria is loaded from the
unchanged local WOFF2 asset with its OFL license, only when selected. No package,
external font host, inline style/CSP exception, or font upload API is added.

## Files and validation

- `apps/dashboard/lib/src/storefront/storefront_content_models.dart`:
  optional shape, HEX validation and error paths.
- `storefront_content_section.dart`: editable text colors using existing draft
  ownership and content save.
- `storefront_copy.dart`, `storefront_section.dart`, `storefront_media_slot.dart`:
  localized labels for colors/background and accurate contrast guidance.
- `supabase/migrations/20261102140930_bizbot_storefront_cinematic_001b_appearance.sql`:
  generated using `npx supabase migration new`; prepared only, not applied.
- Focused dashboard tests cover legacy shape, HEX rejection/normalization,
  immutable draft roundtrip, existing RPC/version arguments, and clearing a
  color. Existing label assertions follow the revised localized copy.
- `supabase/tests/storefront_cinematic_001b_appearance_test.sql` covers strict
  shape, HEX rejection, private/public roundtrip, version/replay, legacy-write
  preservation, table constraint and explicit reset. Fixtures are synthetic
  and the transaction rolls back.
- `git diff --check`: passed. Function-body comparison confirms the SQL changes
  are limited to optional appearance handling.
- Flutter/Dart tests, formatting and pgTAP were not executed: this workspace
  has no Flutter/Dart SDK or local Docker/Postgres runtime. No hosted test or
  migration was run. These focused checks remain required before merge.

## Integration order

The storefront companion must first accept optional `content_v1.appearance`
and map it to theme text/button text tokens, while keeping omitted fields at
the design defaults. Apply the migration through the normal approved deployment
path before enabling the new dashboard color saves. Until then, existing image,
primary and accent controls continue to use the existing contract.

Suggested bounded verification on a prepared local environment:

```sh
flutter test test/storefront_content_test.dart test/storefront_content_section_test.dart test/storefront_section_test.dart test/storefront_media_slot_test.dart
supabase test db supabase/tests/storefront_cinematic_001b_appearance_test.sql
```

Run the Flutter command from `apps/dashboard`, and the Supabase command from the
repository root after local migrations. The standard owner review and merge
gate remains external to this implementation task. No push or merge performed.

## Final font-selection refinement

Prepared on the isolated `feat/BIZBOT-STOREFRONT-CINEMATIC-001B-font-choice`
worktree, starting at `af446b5`. Validation: 20 focused appearance/theme Node
tests, the complete 439-test Storefront Node suite, TypeScript, the fixture
production build, and `git diff --check` pass. The additional font asset is
54,528 bytes and retains the existing site's OFL license. No package manifest
or font preload changed. The production build initially rejected an external
node_modules symlink; a local copy of the already-installed locked dependencies
resolved that environment-only issue.

Dashboard unit/widget cases cover each allowed font, invalid choices, draft
roundtrip, selection and explicit reset. The rollback-only SQL cases cover
validation, existing versioned save/read/public projection, older color-writer
preservation, table-constraint rejection and explicit reset. Flutter/Dart and
local PostgreSQL remain unavailable, so those tests are prepared but unexecuted.
The existing unapplied migration was extended locally; no hosted schema or
tenant setting was changed. Deploy font-aware readers before font-enabled writes.

## 2026-11-03 safe local roundtrip

The followup executed the unchanged migration, existing save/read SQL and
constraints in disposable PostgreSQL 17.5/PGlite, with 18 passing checks and two
consecutive appearance profiles exported into the real Storefront reader and
browser. No application dependency or hosted data changed. This supersedes only
the earlier lack of local SQL execution; Flutter widgets, full Auth/RLS/storage
integration and the complete Supabase pgTAP suite remain untested. Read
`BIZBOT_STOREFRONT_CINEMATIC_001_CLOSEOUT.md` for exact seams, settings readiness,
secondary-screen color limits and remaining reader/migration/writer rollout.
