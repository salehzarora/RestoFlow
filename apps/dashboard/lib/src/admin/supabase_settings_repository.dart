import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

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
    this.restaurantName,
    this.restaurantStatus,
  });

  final String? branchName;

  /// The branch's current status, preserved on save (the write RPC requires a
  /// status; we never silently flip it).
  final String? branchStatus;

  final String? restaurantName;

  /// The restaurant's current status, preserved on save.
  final String? restaurantStatus;
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
}

/// The real, Supabase-backed [SettingsRepository] over `public.list_org_structure`
/// (read) and `public.update_branch_settings` / `public.update_restaurant_settings`
/// (write). Currency is NEVER writable here — the pilot stays ILS-only (Q-007).
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
      return SettingsPrefill(
        branchName: branchName,
        branchStatus: branchStatus,
        restaurantName: _nonEmpty(r['name']),
        restaurantStatus: _nonEmpty(r['status']),
      );
    }
    return null;
  }

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
        // Currency stays locked (ILS-only pilot); timezone is not edited here.
        'p_currency_override': null,
        'p_timezone': null,
        'p_status': status,
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
