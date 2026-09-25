import 'package:restoflow_l10n/restoflow_l10n.dart';

/// STOREFRONT-PUBLISH-001 — the localized copy of the profile writer's server
/// codes, shared by the Settings "Storefront" card and its media slots: a
/// refused slot assignment shows the SAME per-reason copy and blocker labels
/// as a refused form save (never a generic "try again later" for a
/// deterministic refusal).

/// The localized copy of a writer `invalid` reason (unknown codes fall back to
/// a generic line carrying the code).
String storefrontReasonMessage(AppLocalizations l10n, String? reason) =>
    switch (reason) {
      'slug_invalid' => l10n.storefrontReasonSlugInvalid,
      'slug_immutable' => l10n.storefrontReasonSlugImmutable,
      'slug_taken' => l10n.storefrontReasonSlugTaken,
      'branch_invalid' => l10n.storefrontReasonBranchInvalid,
      'display_name_invalid' => l10n.storefrontReasonDisplayNameInvalid,
      'tagline_invalid' => l10n.storefrontReasonTaglineInvalid,
      'public_city_invalid' => l10n.storefrontReasonPublicCityInvalid,
      'public_address_invalid' => l10n.storefrontReasonPublicAddressInvalid,
      'public_phone_invalid' => l10n.storefrontReasonPublicPhoneInvalid,
      'primary_color_invalid' => l10n.storefrontReasonPrimaryColorInvalid,
      'accent_color_invalid' => l10n.storefrontReasonAccentColorInvalid,
      'visual_preset_invalid' => l10n.storefrontReasonVisualPresetInvalid,
      'locale_default_invalid' => l10n.storefrontReasonLocaleDefaultInvalid,
      'card_mode_invalid' => l10n.storefrontReasonCardModeInvalid,
      'motion_invalid' => l10n.storefrontReasonMotionInvalid,
      'pickup_enabled_invalid' => l10n.storefrontReasonPickupEnabledInvalid,
      'paused_until_invalid' => l10n.storefrontReasonPausedUntilInvalid,
      'pause_reason_invalid' => l10n.storefrontReasonPauseReasonInvalid,
      'opening_hours_invalid' => l10n.storefrontReasonOpeningHoursInvalid,
      'logo_media_id_invalid' => l10n.storefrontReasonLogoMediaIdInvalid,
      'hero_media_id_invalid' => l10n.storefrontReasonHeroMediaIdInvalid,
      'is_published_invalid' => l10n.storefrontReasonIsPublishedInvalid,
      'branch_missing' => l10n.storefrontReasonBranchMissing,
      'slug_missing' => l10n.storefrontReasonSlugMissing,
      'publish_precondition' => l10n.storefrontReasonPublishPrecondition,
      'unknown_field' => l10n.storefrontReasonUnknownField,
      'patch_not_object' => l10n.storefrontReasonPatchNotObject,
      _ => l10n.storefrontErrorInvalid(reason ?? '-'),
    };

/// The Dashboard's OWN publish blocker (not a server code): the SAVED opening
/// hours hold entries the editor cannot read (see
/// `OpeningHours.hasUnreadableEntries`). The server's blockers cannot see it
/// — the database check accepts such a value — so the card adds it: Publish
/// stays disabled and "all requirements met" is never claimed until the
/// hours are repaired and saved.
const String kStorefrontClientBlockerHoursUnreadable = 'hours_unreadable';

/// The localized label of a publish blocker, saying where to fix it (unknown
/// codes fall back to a generic line carrying the code).
String storefrontBlockerLabel(AppLocalizations l10n, String code) =>
    switch (code) {
      'slug_missing' => l10n.storefrontBlockerSlugMissing,
      'branch_missing' => l10n.storefrontBlockerBranchMissing,
      'timezone_missing' => l10n.storefrontBlockerTimezoneMissing,
      'currency_not_ils' => l10n.storefrontBlockerCurrencyNotIls,
      'tax_not_exclusive' => l10n.storefrontBlockerTaxNotExclusive,
      'no_live_item' => l10n.storefrontBlockerNoLiveItem,
      'hours_missing' => l10n.storefrontBlockerHoursMissing,
      kStorefrontClientBlockerHoursUnreadable =>
        l10n.storefrontBlockerHoursUnreadable,
      _ => l10n.storefrontBlockerUnknown(code),
    };
