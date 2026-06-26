/// The RF-112 settings slice (API_CONTRACT §4.25 / D-033) — existing columns only.
/// Deliberately EXCLUDES tax, rounding, locale, business hours, and receipt
/// template/logo/header/footer (each is a separate ticket).

/// The two allowed status values across the hierarchy (§2.1–§2.3).
const List<String> kSettingsStatuses = ['active', 'suspended'];

/// Organization settings: default_currency, country_code, status.
class OrganizationSettings {
  const OrganizationSettings({
    required this.defaultCurrency,
    required this.countryCode,
    required this.status,
  });

  final String defaultCurrency; // ISO-4217 alpha-3 (e.g. USD)
  final String? countryCode; // ISO alpha-2 (e.g. US); nullable
  final String status;

  OrganizationSettings copyWith({
    String? defaultCurrency,
    String? countryCode,
    String? status,
  }) => OrganizationSettings(
    defaultCurrency: defaultCurrency ?? this.defaultCurrency,
    countryCode: countryCode ?? this.countryCode,
    status: status ?? this.status,
  );
}

/// Restaurant settings: name, currency_override, timezone, status.
class RestaurantSettings {
  const RestaurantSettings({
    required this.name,
    required this.currencyOverride,
    required this.timezone,
    required this.status,
  });

  final String name;
  final String? currencyOverride;
  final String? timezone;
  final String status;

  RestaurantSettings copyWith({
    String? name,
    String? currencyOverride,
    String? timezone,
    String? status,
  }) => RestaurantSettings(
    name: name ?? this.name,
    currencyOverride: currencyOverride ?? this.currencyOverride,
    timezone: timezone ?? this.timezone,
    status: status ?? this.status,
  );
}

/// Branch settings: name, address, timezone, receipt_prefix, status.
class BranchSettings {
  const BranchSettings({
    required this.name,
    required this.address,
    required this.timezone,
    required this.receiptPrefix,
    required this.status,
  });

  final String name;
  final String? address;
  final String? timezone;
  final String? receiptPrefix;
  final String status;

  BranchSettings copyWith({
    String? name,
    String? address,
    String? timezone,
    String? receiptPrefix,
    String? status,
  }) => BranchSettings(
    name: name ?? this.name,
    address: address ?? this.address,
    timezone: timezone ?? this.timezone,
    receiptPrefix: receiptPrefix ?? this.receiptPrefix,
    status: status ?? this.status,
  );
}

/// The full settings bundle for the active scope.
class SettingsBundle {
  const SettingsBundle({
    required this.organization,
    required this.restaurant,
    required this.branch,
  });

  final OrganizationSettings organization;
  final RestaurantSettings restaurant;
  final BranchSettings branch;

  SettingsBundle copyWith({
    OrganizationSettings? organization,
    RestaurantSettings? restaurant,
    BranchSettings? branch,
  }) => SettingsBundle(
    organization: organization ?? this.organization,
    restaurant: restaurant ?? this.restaurant,
    branch: branch ?? this.branch,
  );
}
