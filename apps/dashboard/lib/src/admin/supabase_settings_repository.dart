import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

import 'timezone_catalog.dart';

/// The outcome of a settings write (RF-116).
enum SettingsWrite {
  /// The owner's change was applied.
  ok,

  /// The caller's role may not change these settings (rank < restaurant_owner).
  denied,

  /// A transport/session/validation failure — nothing changed; show an honest
  /// error and keep the displayed value.
  unavailable,
}

/// The current, readable settings values for a concrete (restaurant, branch)
/// scope, prefilled from `public.list_org_structure`. Only the NAME and STATUS
/// are readable there — receipt prefix / address / country code are NOT, so those
/// form fields start blank and a NULL text param leaves them unchanged.
class SettingsPrefill {
  const SettingsPrefill({
    this.branchName,
    this.branchStatus,
    this.branchTimezone,
    this.restaurantName,
    this.restaurantStatus,
    this.restaurantCurrencyOverride,
    this.organizationDefaultCurrency,
  });

  final String? branchName;

  /// The branch's current status, preserved on save (the write RPC requires a
  /// status; we never silently flip it).
  final String? branchStatus;

  /// The branch's CURRENT IANA timezone (from `list_org_structure`), so the
  /// picker can SHOW what is set (e.g. an unset/`UTC` pilot branch) — not just
  /// let the owner blindly change it. Null when the branch has no timezone.
  final String? branchTimezone;

  final String? restaurantName;

  /// The restaurant's current status, preserved on save.
  final String? restaurantStatus;

  /// OPS-043 D1: `restaurants.currency_override` AS STORED — null means this
  /// restaurant inherits. The already-coalesced effective currency on
  /// `ResolvedTenantContext` cannot answer "is this inherited or set?", which
  /// is exactly what the Operating currency row has to tell the owner.
  final String? restaurantCurrencyOverride;

  /// OPS-043 D1: `organizations.default_currency` — the value inherited when
  /// [restaurantCurrencyOverride] is null.
  final String? organizationDefaultCurrency;

  /// The currency this restaurant actually operates in:
  /// `coalesce(restaurants.currency_override, organizations.default_currency)`,
  /// the same rule the menu/POS RPCs apply server-side.
  String? get effectiveCurrency =>
      restaurantCurrencyOverride ?? organizationDefaultCurrency;

  /// True when the currency comes from the organization rather than from this
  /// restaurant's own override.
  bool get currencyIsInherited => restaurantCurrencyOverride == null;
}

/// Reads current (branch/restaurant) settings and writes the editable subset via
/// the `public.update_*_settings` RPCs over the authenticated dashboard transport.
/// Pre-scoped to a single (org, restaurant, branch); the server derives the actor
/// from `auth.uid()` and enforces the owner gate (rank >= restaurant_owner — the
/// server denies managers) — this seam never sends identity or a service-role key
/// (DECISION D-011). Faked in widget tests.
abstract interface class SettingsRepository {
  /// The current readable values, or null when they cannot be read (fail-soft —
  /// the caller then falls back to the membership names, never a fabricated one).
  Future<SettingsPrefill?> readPrefill();

  /// The global IANA timezone catalog for the picker (from `list_timezones`),
  /// or an empty list on failure (fail-soft — the picker degrades gracefully).
  Future<List<TimezoneOption>> loadTimezones();

  /// Writes the branch display name (+ optional receipt prefix; blank = leave
  /// unchanged). [status] preserves the branch's current status. [timezone] is an
  /// IANA zone to set (e.g. `Asia/Jerusalem`) or null to leave it unchanged —
  /// correcting it fixes reporting's branch-local hour/day bucketing
  /// (RF-REPORT-004).
  Future<SettingsWrite> saveBranch({
    required String name,
    String? receiptPrefix,
    required String status,
    String? timezone,
  });

  /// Writes the restaurant display name. [status] preserves the current status.
  Future<SettingsWrite> saveRestaurant({
    required String name,
    required String status,
  });

  /// OPS-043 D1: sets `restaurants.currency_override` for THIS restaurant only.
  ///
  /// Deliberately its own method rather than another parameter on
  /// [saveRestaurant]: the two are separate owner intents with separate
  /// confirmations, and folding the currency into the name save would put it
  /// under the same idempotency fingerprint.
  ///
  /// It can only SET. `update_restaurant_settings` applies the value with
  /// `coalesce(v_cur, currency_override)`, so a null argument means "leave
  /// unchanged" and there is NO server path back to inheritance — see
  /// [SettingsPrefill.currencyIsInherited]. It also never touches sibling
  /// restaurants: the write is scoped to `p_restaurant_id`, and
  /// `organizations.default_currency` is not written here at all.
  Future<SettingsWrite> saveOperatingCurrency({required String currencyCode});
}

/// The real, Supabase-backed [SettingsRepository] over `public.list_org_structure`
/// (read) and `public.update_branch_settings` / `public.update_restaurant_settings`
/// (write). OPS-043 D1 replaced the ILS-only lock (Q-007) with a real
/// restaurant-level Operating currency: [saveOperatingCurrency] writes
/// `restaurants.currency_override` for THIS restaurant, and nothing here ever
/// writes `organizations.default_currency`.
class SupabaseSettingsRepository implements SettingsRepository {
  SupabaseSettingsRepository({
    required SyncRpcTransport transport,
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    int Function()? nonce,
  }) : _t = transport,
       _nonce = nonce ?? _microNonce;

  final SyncRpcTransport _t;
  final String organizationId;
  final String restaurantId;
  final String branchId;
  final int Function() _nonce;

  static int _microNonce() => DateTime.now().microsecondsSinceEpoch;

  @override
  Future<SettingsPrefill?> readPrefill() async {
    final Object? raw;
    try {
      raw = await _t.invoke('list_org_structure', <String, dynamic>{
        'p_organization_id': organizationId,
      });
    } catch (_) {
      return null;
    }
    if (raw is! Map || raw['ok'] != true) return null;
    final organization = raw['organization'];
    final orgDefaultCurrency = organization is Map
        ? organization['default_currency']
        : null;
    for (final r in (raw['restaurants'] as List?) ?? const []) {
      if (r is! Map || (r['id'] ?? '').toString() != restaurantId) continue;
      String? branchName;
      String? branchStatus;
      for (final b in (r['branches'] as List?) ?? const []) {
        if (b is! Map || (b['id'] ?? '').toString() != branchId) continue;
        branchName = _nonEmpty(b['name']);
        branchStatus = _nonEmpty(b['status']);
        break;
      }
      String? branchTimezone;
      for (final b in (r['branches'] as List?) ?? const []) {
        if (b is! Map || (b['id'] ?? '').toString() != branchId) continue;
        branchTimezone = _nonEmpty(b['timezone']);
        break;
      }
      return SettingsPrefill(
        branchName: branchName,
        branchStatus: branchStatus,
        branchTimezone: branchTimezone,
        restaurantName: _nonEmpty(r['name']),
        restaurantStatus: _nonEmpty(r['status']),
        // OPS-043: the RAW pair, never pre-coalesced — the settings row has to
        // distinguish "inherited from the organization" from "set here".
        restaurantCurrencyOverride: _nonEmpty(r['currency_override']),
        organizationDefaultCurrency: _nonEmpty(orgDefaultCurrency),
      );
    }
    return null;
  }

  @override
  Future<List<TimezoneOption>> loadTimezones() async {
    final Object? raw;
    try {
      raw = await _t.invoke('list_timezones', const <String, dynamic>{});
    } catch (_) {
      return const [];
    }
    if (raw is! Map || raw['ok'] != true) return const [];
    final zones = raw['zones'];
    if (zones is! List) return const [];
    final out = <TimezoneOption>[];
    for (final z in zones) {
      if (z is! Map) continue;
      final id = (z['id'] ?? '').toString();
      if (id.isEmpty) continue;
      out.add(TimezoneOption(id: id, offsetMinutes: _int(z['offset_minutes'])));
    }
    return out;
  }

  static int _int(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;

  static String? _nonEmpty(Object? v) {
    final s = (v ?? '').toString();
    return s.isEmpty ? null : s;
  }

  @override
  Future<SettingsWrite> saveBranch({
    required String name,
    String? receiptPrefix,
    required String status,
    String? timezone,
  }) async {
    final Object? raw;
    try {
      raw = await _t.invoke('update_branch_settings', <String, dynamic>{
        'p_client_request_id': _requestId('branch', [
          name,
          receiptPrefix ?? '',
          status,
          timezone ?? '',
        ]),
        'p_organization_id': organizationId,
        'p_restaurant_id': restaurantId,
        'p_branch_id': branchId,
        'p_name': name,
        // A NULL text param leaves the field unchanged (address is not edited
        // here; a blank receipt prefix / unset timezone leaves it unchanged).
        // RF-REPORT-004: a non-null timezone corrects the branch-local reporting
        // bucketing (the server validates it against pg_timezone_names).
        'p_address': null,
        'p_timezone': timezone,
        'p_receipt_prefix': receiptPrefix,
        'p_status': status,
      });
    } catch (_) {
      return SettingsWrite.unavailable;
    }
    return _outcome(raw);
  }

  @override
  Future<SettingsWrite> saveRestaurant({
    required String name,
    required String status,
  }) async {
    final Object? raw;
    try {
      raw = await _t.invoke('update_restaurant_settings', <String, dynamic>{
        'p_client_request_id': _requestId('restaurant', [name, status]),
        'p_organization_id': organizationId,
        'p_restaurant_id': restaurantId,
        'p_name': name,
        // The name save must not touch the currency: null means "leave
        // unchanged" (the RPC coalesces), and the currency has its own
        // confirmed write in [saveOperatingCurrency]. Timezone is not edited
        // here either.
        'p_currency_override': null,
        'p_timezone': null,
        'p_status': status,
      });
    } catch (_) {
      return SettingsWrite.unavailable;
    }
    return _outcome(raw);
  }

  @override
  Future<SettingsWrite> saveOperatingCurrency({
    required String currencyCode,
  }) async {
    final code = currencyCode.trim().toUpperCase();
    // Fail closed on a malformed code rather than letting the server raise
    // 42501 (which surfaces as an opaque "unavailable").
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(code)) {
      return SettingsWrite.unavailable;
    }
    final Object? raw;
    try {
      raw = await _t.invoke('update_restaurant_settings', <String, dynamic>{
        // The currency is part of the fingerprint: two different currency
        // saves must never collide on the server's management ledger.
        'p_client_request_id': _requestId('restaurant-currency', [code]),
        'p_organization_id': organizationId,
        'p_restaurant_id': restaurantId,
        // THIS restaurant only. Null name/timezone/status leave those fields
        // untouched (the RPC coalesces), and no organization-level currency is
        // written — sibling restaurants keep their own currency (D1).
        'p_name': null,
        'p_currency_override': code,
        'p_timezone': null,
        'p_status': null,
      });
    } catch (_) {
      return SettingsWrite.unavailable;
    }
    return _outcome(raw);
  }

  SettingsWrite _outcome(Object? raw) {
    if (raw is! Map) return SettingsWrite.unavailable;
    if (raw['ok'] == true) return SettingsWrite.ok;
    return raw['error'] == 'permission_denied'
        ? SettingsWrite.denied
        : SettingsWrite.unavailable;
  }

  /// A fresh v5-style idempotency key per deliberate Save press (the server
  /// ledger keys retries; a per-press nonce makes each press its own request,
  /// mirroring the RF-113 shift-close policy repo).
  String _requestId(String op, List<String> parts) {
    final seed = [op, ...parts, _nonce().toString()].join('|');
    final bytes = sha256
        .convert(utf8.encode('rf116:settings:$seed'))
        .bytes
        .sublist(0, 16);
    bytes[6] = (bytes[6] & 0x0f) | 0x50; // version 5 (name-based)
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC-4122 variant
    String hx(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hx(0, 4)}-${hx(4, 6)}-${hx(6, 8)}-${hx(8, 10)}-${hx(10, 16)}';
  }
}
