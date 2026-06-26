/// Small fail-closed JSON readers shared by the menu model `fromJson` factories
/// (RF-111). Required fields throw [FormatException] on a missing/wrong type;
/// optional readers fall back. These back future real reads (sync_pull / direct
/// table SELECT); the demo/in-memory path constructs models directly.
library;

String requireString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || value.isEmpty) {
    throw FormatException('$key missing or not a non-empty string');
  }
  return value;
}

String? optString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String) return value;
  throw FormatException('$key not a string or null');
}

int requireInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is int) return value;
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('$key missing or not an integer');
}

int optInt(Map<String, dynamic> json, String key, int fallback) {
  final value = json[key];
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('$key not an integer');
}

int? optIntOrNull(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is int) return value;
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw FormatException('$key not an integer or null');
}

bool optBool(Map<String, dynamic> json, String key, bool fallback) {
  final value = json[key];
  if (value == null) return fallback;
  if (value is bool) return value;
  throw FormatException('$key not a boolean');
}

DateTime? parseTimestamp(Object? value) {
  if (value == null) return null;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
