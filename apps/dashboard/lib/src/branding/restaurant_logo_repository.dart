import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';

/// PRINT-BRANDING-LOGO-001 — the current restaurant receipt-branding settings.
class RestaurantLogoSettings {
  const RestaurantLogoSettings({
    required this.path,
    required this.enabled,
    required this.version,
    this.canManage = false,
  });

  /// The object key of the current logo (null = none).
  final String? path;

  /// Whether the logo prints on customer receipts.
  final bool enabled;

  /// The monotonic branding version (>=0) — sent as expected_version on save.
  final int version;

  /// PRINT-BRANDING-LOGO-001 (§10): the BACKEND capability signal — whether the
  /// current actor may MANAGE branding (org_owner/restaurant_owner/restaurant-
  /// level manager). The Dashboard keys editability on this, never the literal
  /// role name; a branch-only manager / cashier / accountant reads but cannot
  /// manage. Populated by the read RPC; false for a write result.
  final bool canManage;

  bool get hasLogo => path != null && path!.isNotEmpty;
}

/// The classified outcome of a branding write (§9 — never a bare `false`).
enum RestaurantLogoWriteStatus {
  /// The change was applied; [RestaurantLogoWriteResult.settings] is authoritative.
  ok,

  /// The caller's role may not manage branding.
  denied,

  /// Someone else changed branding first (stale expected_version);
  /// [RestaurantLogoWriteResult.settings] carries the CURRENT authoritative state.
  conflict,

  /// The request was structurally invalid (bad path / enable-with-null).
  invalid,

  /// The RPC RESPONDED but rejected the write for an unrecognised reason — no
  /// commit happened, so the caller may clean up its just-uploaded orphan.
  unavailable,

  /// The storage object upload/delete failed (set by the workflow layer).
  storageFailure,

  /// A readback CONFIRMED the write did not commit (authoritative version is
  /// still the expected one) — the caller may delete its just-uploaded orphan.
  notCommitted,

  /// The outcome is UNKNOWN: neither the RPC (even after an idempotent retry) nor
  /// a readback could determine whether the write committed. The caller must
  /// delete NOTHING — an orphan is safer than deleting an authoritative object —
  /// and offer a refresh/retry.
  uncertain,
}

/// A branding write result. On [ok]/[conflict] it carries the authoritative
/// [settings] so the UI can refresh to the true current state.
class RestaurantLogoWriteResult {
  const RestaurantLogoWriteResult(this.status, {this.settings});

  final RestaurantLogoWriteStatus status;
  final RestaurantLogoSettings? settings;

  bool get isOk => status == RestaurantLogoWriteStatus.ok;
}

/// Reads + writes restaurant receipt branding via the CAS RPC. The server
/// derives the actor from `auth.uid()` and enforces the named-role gate
/// (org_owner/restaurant_owner/manager); this seam sends no identity and no
/// service-role key (D-011). Faked in widget tests.
abstract interface class RestaurantLogoRepository {
  /// The current settings, or null when they cannot be read (fail-soft).
  Future<RestaurantLogoSettings?> read();

  /// Compare-and-set the branding. [expectedVersion] must match the server's
  /// current version or the write returns [RestaurantLogoWriteStatus.conflict]
  /// with the authoritative settings. A null [path] removes the logo (forces
  /// disabled).
  Future<RestaurantLogoWriteResult> save({
    required String? path,
    required bool enabled,
    required int expectedVersion,
  });
}

/// The real, Supabase-backed [RestaurantLogoRepository] over
/// `public.get_restaurant_receipt_logo` / `public.set_restaurant_receipt_logo`.
class SupabaseRestaurantLogoRepository implements RestaurantLogoRepository {
  SupabaseRestaurantLogoRepository({
    required SyncRpcTransport transport,
    required this.organizationId,
    required this.restaurantId,
    int Function()? nonce,
  }) : _t = transport,
       _nonce = nonce ?? _microNonce;

  final SyncRpcTransport _t;
  final String organizationId;
  final String restaurantId;
  final int Function() _nonce;

  static int _microNonce() => DateTime.now().microsecondsSinceEpoch;

  @override
  Future<RestaurantLogoSettings?> read() async {
    final Object? raw;
    try {
      raw = await _t.invoke('get_restaurant_receipt_logo', <String, dynamic>{
        'p_organization_id': organizationId,
        'p_restaurant_id': restaurantId,
      });
    } catch (_) {
      return null;
    }
    if (raw is! Map || raw['ok'] != true) return null;
    // can_manage is a READ-only capability signal (the write RPC never returns it).
    return _settingsFrom(raw, canManage: raw['can_manage'] == true);
  }

  @override
  Future<RestaurantLogoWriteResult> save({
    required String? path,
    required bool enabled,
    required int expectedVersion,
  }) async {
    // ONE STABLE idempotency id for this logical save, so an ambiguous-outcome
    // RETRY replays the SAME request: a committed write returns its stored result
    // via the server ledger (never a duplicate mutation, never a second version
    // bump). §7.
    final requestId = _requestId([
      path ?? '',
      enabled.toString(),
      expectedVersion.toString(),
    ]);

    // Attempt once; on a TRANSPORT failure retry EXACTLY once with the SAME id.
    var raw = await _tryInvokeSave(requestId, path, enabled, expectedVersion);
    raw ??= await _tryInvokeSave(requestId, path, enabled, expectedVersion);
    if (raw != null) return _classifyWrite(raw);

    // Neither attempt reached the server — reconcile against the authoritative
    // state so we NEVER delete a possibly-committed object on a lost response.
    return _reconcile(path, enabled, expectedVersion);
  }

  /// Invoke the CAS RPC; returns the raw Map response, or null on a transport
  /// failure / non-map response (the ambiguous case that triggers reconciliation).
  Future<Map<dynamic, dynamic>?> _tryInvokeSave(
    String requestId,
    String? path,
    bool enabled,
    int expectedVersion,
  ) async {
    try {
      final raw = await _t
          .invoke('set_restaurant_receipt_logo', <String, dynamic>{
            'p_client_request_id': requestId,
            'p_organization_id': organizationId,
            'p_restaurant_id': restaurantId,
            'p_logo_path': path,
            'p_enabled': enabled,
            'p_expected_version': expectedVersion,
          });
      return raw is Map ? raw : null;
    } catch (_) {
      return null;
    }
  }

  RestaurantLogoWriteResult _classifyWrite(Map<dynamic, dynamic> raw) {
    if (raw['ok'] == true) {
      return RestaurantLogoWriteResult(
        RestaurantLogoWriteStatus.ok,
        settings: _settingsFrom(raw),
      );
    }
    switch (raw['error']) {
      case 'version_conflict':
        return RestaurantLogoWriteResult(
          RestaurantLogoWriteStatus.conflict,
          settings: _settingsFrom(raw),
        );
      case 'permission_denied':
        return const RestaurantLogoWriteResult(
          RestaurantLogoWriteStatus.denied,
        );
      case 'invalid':
        return const RestaurantLogoWriteResult(
          RestaurantLogoWriteStatus.invalid,
        );
      default:
        // A RESPONDED-but-unrecognised error means no commit happened.
        return const RestaurantLogoWriteResult(
          RestaurantLogoWriteStatus.unavailable,
        );
    }
  }

  /// Read the authoritative state and decide whether the (lost-response) write
  /// committed. Never deletes anything — it only classifies for the caller.
  Future<RestaurantLogoWriteResult> _reconcile(
    String? path,
    bool enabled,
    int expectedVersion,
  ) async {
    final current = await read();
    if (current == null) {
      // Can't read authority => truly uncertain: delete NOTHING.
      return const RestaurantLogoWriteResult(
        RestaurantLogoWriteStatus.uncertain,
      );
    }
    if (current.version == expectedVersion) {
      // The authoritative version never advanced => our write did NOT commit.
      return RestaurantLogoWriteResult(
        RestaurantLogoWriteStatus.notCommitted,
        settings: current,
      );
    }
    if (current.version == expectedVersion + 1 &&
        current.path == path &&
        current.enabled == enabled) {
      // The version advanced exactly once TO our intended state => WE committed.
      return RestaurantLogoWriteResult(
        RestaurantLogoWriteStatus.ok,
        settings: current,
      );
    }
    // The version advanced but not to our intended state => someone else won.
    return RestaurantLogoWriteResult(
      RestaurantLogoWriteStatus.conflict,
      settings: current,
    );
  }

  RestaurantLogoSettings _settingsFrom(
    Map<dynamic, dynamic> raw, {
    bool canManage = false,
  }) {
    final path = raw['receipt_logo_path'];
    return RestaurantLogoSettings(
      path: (path == null || '$path'.isEmpty) ? null : '$path',
      enabled: raw['receipt_logo_enabled'] == true,
      version: raw['receipt_logo_version'] is int
          ? raw['receipt_logo_version'] as int
          : int.tryParse('${raw['receipt_logo_version']}') ?? 0,
      canManage: canManage,
    );
  }

  /// A fresh v5 idempotency key per deliberate press (server ledger keys retries).
  String _requestId(List<String> parts) {
    final seed = [...parts, _nonce().toString()].join('|');
    final bytes = sha256
        .convert(utf8.encode('pbl:logo:$seed'))
        .bytes
        .sublist(0, 16);
    bytes[6] = (bytes[6] & 0x0f) | 0x50; // version 5
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC-4122 variant
    String hx(int start, int end) => bytes
        .sublist(start, end)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hx(0, 4)}-${hx(4, 6)}-${hx(6, 8)}-${hx(8, 10)}-${hx(10, 16)}';
  }
}
