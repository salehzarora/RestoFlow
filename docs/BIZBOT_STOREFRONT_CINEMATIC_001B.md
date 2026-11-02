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
The controls accept six-digit HEX values, show a swatch, and restore the design
default when left blank. Existing warnings now ask the editor to check contrast
without claiming the storefront will replace their selected color.

## Contract extension

The private content document and public `content_v1` may contain:

```json
{
  "appearance": {
    "text_color": "#fff4e6",
    "button_text_color": "#14120f"
  }
}
```

- `appearance` is optional. When present it is an object containing exactly
  both keys above. Unknown keys, a null object, and missing child keys fail.
- Each value is either null or exactly `#` plus six hexadecimal digits.
  Uppercase input is accepted and normalized to lowercase. Named colors,
  shorthand, alpha channels, whitespace and CSS expressions fail.
- A null value means use the storefront default for that color.
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
