/// POS-OFFLINE-OPERATIONS-002 — the durable, SCOPE-PARTITIONED operational
/// snapshot: everything a till needs to KEEP SELLING when the backend is
/// unreachable, captured from real fetch results while it was online.
///
/// The snapshot is written on every successful `pos_menu` fetch (and its
/// kitchen-mode field refreshed whenever a verified mode resolves) and read
/// back ONLY when a real fetch fails — it is a fallback, never a source of
/// truth, and Supabase remains authoritative for everything in it (D-010:
/// the cache is an enhancement of availability, not a second truth).
///
/// It is keyed by the FULL operational scope (organization, restaurant,
/// branch, device) exactly like the pull cursor and the parked carts: a till
/// moved to another branch, or re-paired as another device, must never sell
/// from somebody else's menu. The scope ids are ALSO embedded inside the
/// payload and verified on read, so even a byte-for-byte copy under another
/// scope's key reads as ABSENT.
///
/// FORBIDDEN CONTENT (SECURITY REQUIREMENT): no PINs, no tokens, no
/// enrollment codes, no anon keys, and nothing cross-tenant — the snapshot
/// carries display names, capability booleans, integer minor prices and
/// policy values only.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show BranchTax;
import 'package:restoflow_core/restoflow_core.dart' show Success;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show
        KitchenModePrinterOnlyWithRevision,
        KitchenModeResult,
        KitchenModeVerifiedKds;
import 'package:shared_preferences/shared_preferences.dart';

import '../state/discount_controller.dart' show staffCapabilitiesProvider;
import '../state/pos_branch_tax.dart' show posBranchTaxProvider;
import '../state/pos_menu_provider.dart' show PosMenuData;
import '../state/pos_printer_assignments.dart'
    show posPrinterAssignmentsProvider, posRestaurantNameProvider;
import '../state/pos_session.dart'
    show posSignedInEmployeeProfileIdProvider, posSignedInStaffNameProvider;
import '../state/pos_shift.dart' show posOpenShiftProvider;
import '../state/pos_sync_scope_provider.dart' show posSyncScopeProvider;
import 'kitchen_mode_readiness.dart' show posVerifiedKitchenModeProvider;
import 'operational_snapshot_codec.dart';
import 'sync_cursor_store.dart' show PosPersistenceException, PosSyncScope;

/// The storage key for one scope's operational snapshot.
///
/// [PosSyncScope.key] is already preferences-safe; the sanitizer is re-applied
/// here so this key is provably safe on its own terms rather than by trusting
/// a caller. Two different scopes can never collide onto one key.
String operationalSnapshotStorageKey(PosSyncScope scope) {
  final safe = scope.key.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
  return 'restoflow.pos.operational_snapshot.v1.$safe';
}

/// The VERIFIED kitchen workflow mode captured into the snapshot — the server
/// verdict's mode + revision + when the SERVER verified it. [verifiedAt] is
/// the trust anchor for the later offline acceptance window, so it is only
/// ever the server-verified time, never a local read-back time.
class PosSnapshotKitchenMode {
  const PosSnapshotKitchenMode({
    required this.mode,
    required this.verifiedAt,
    this.revision,
  });

  /// `'kds'` or `'printer_only'` (the only two verified shapes).
  final String mode;
  final int? revision;
  final DateTime verifiedAt;

  /// The snapshot form of a live [KitchenModeResult]: only a VERIFIED mode
  /// (kds, or printer_only WITH a revision) is persistable — every failure
  /// shape yields null so an unverified guess can never be cached as trust.
  static PosSnapshotKitchenMode? fromResult(KitchenModeResult? result) =>
      switch (result) {
        KitchenModeVerifiedKds(:final verifiedAt, :final revision) =>
          PosSnapshotKitchenMode(
            mode: 'kds',
            revision: revision,
            verifiedAt: verifiedAt,
          ),
        KitchenModePrinterOnlyWithRevision(
          :final revision,
          :final verifiedAt,
        ) =>
          PosSnapshotKitchenMode(
            mode: 'printer_only',
            revision: revision,
            verifiedAt: verifiedAt,
          ),
        _ => null,
      };

  Map<String, Object?> toJson() => <String, Object?>{
    'mode': mode,
    if (revision != null) 'revision': revision,
    'verified_at': verifiedAt.toIso8601String(),
  };

  static PosSnapshotKitchenMode? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final mode = raw['mode'];
    if (mode != 'kds' && mode != 'printer_only') return null;
    final verifiedAt = DateTime.tryParse('${raw['verified_at'] ?? ''}');
    if (verifiedAt == null) return null;
    final revision = raw['revision'];
    return PosSnapshotKitchenMode(
      mode: mode as String,
      revision: revision is int && revision > 0 ? revision : null,
      verifiedAt: verifiedAt.toUtc(),
    );
  }
}

/// A REFERENCE to the open shift at capture time (id + opened-at only — the
/// authoritative money summary stays server-side and is never cached).
class PosSnapshotShiftRef {
  const PosSnapshotShiftRef({required this.id, required this.openedAt});

  final String id;
  final DateTime openedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'opened_at': openedAt.toIso8601String(),
  };

  static PosSnapshotShiftRef? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final openedAt = DateTime.tryParse('${raw['opened_at'] ?? ''}');
    if (openedAt == null) return null;
    return PosSnapshotShiftRef(id: id, openedAt: openedAt.toUtc());
  }
}

/// One scope's captured operational snapshot. Optional context that was not
/// loaded at capture time is stored NULL — an absent capability probe or tax
/// read must never block persisting the menu the till needs to keep selling.
class PosOperationalSnapshot {
  const PosOperationalSnapshot({
    required this.organizationId,
    required this.restaurantId,
    required this.branchId,
    required this.deviceId,
    required this.menu,
    required this.fetchedAt,
    this.restaurantName,
    this.branchName,
    this.stationName,
    this.employeeProfileId,
    this.employeeDisplayName,
    this.capabilities,
    this.tax,
    this.kitchenMode,
    this.openShift,
    this.printerPurposeMeta = const <Object?>[],
    this.sourceRevision,
  });

  /// Bump ONLY on an incompatible envelope shape change. An unrecognised
  /// version is REFUSED on load rather than mis-parsed.
  static const int schemaVersion = 1;

  /// The scope this snapshot was captured for — embedded in the payload AND in
  /// the storage key, and verified against each other on read.
  final String organizationId;
  final String restaurantId;
  final String branchId;
  final String deviceId;

  /// Display identity from the same token-proven sources the top bar uses.
  final String? restaurantName;
  final String? branchName;
  final String? stationName;

  /// The signed-in operator at capture time (identity id + display text only —
  /// NEVER a PIN, hash, or token).
  final String? employeeProfileId;
  final String? employeeDisplayName;

  /// The server-resolved capability map in the SAME wire shape
  /// `pin_session_capabilities` serves (so a restore can feed the existing
  /// parser). Null when the probe had not resolved at capture time.
  final Map<String, Object?>? capabilities;

  /// The FULL menu the POS sells from, reconstructable offline.
  final PosMenuData menu;

  /// The branch tax policy at capture time (integer basis points, D-007), or
  /// null when the tax read had not resolved.
  final BranchTax? tax;

  /// The last VERIFIED kitchen workflow mode, or null when none had resolved.
  final PosSnapshotKitchenMode? kitchenMode;

  /// The open-shift reference, or null when no server shift handle was held.
  final PosSnapshotShiftRef? openShift;

  /// Printer PURPOSE metadata only (which printer serves which purpose slot) —
  /// endpoints/transport configs already persist through their own stores and
  /// are deliberately NOT duplicated here.
  final List<Object?> printerPurposeMeta;

  /// When the menu in this snapshot was FETCHED from the server.
  final DateTime fetchedAt;

  /// The server menu revision, when one is ever served (`pos_menu` carries
  /// none today — stored null so the field is additive later).
  final int? sourceRevision;

  /// A copy with only the kitchen-mode capture replaced (the read-modify-swap
  /// partial update the lifecycle's mode listener performs).
  PosOperationalSnapshot withKitchenMode(PosSnapshotKitchenMode kitchenMode) =>
      PosOperationalSnapshot(
        organizationId: organizationId,
        restaurantId: restaurantId,
        branchId: branchId,
        deviceId: deviceId,
        menu: menu,
        fetchedAt: fetchedAt,
        restaurantName: restaurantName,
        branchName: branchName,
        stationName: stationName,
        employeeProfileId: employeeProfileId,
        employeeDisplayName: employeeDisplayName,
        capabilities: capabilities,
        tax: tax,
        kitchenMode: kitchenMode,
        openShift: openShift,
        printerPurposeMeta: printerPurposeMeta,
        sourceRevision: sourceRevision,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'organization_id': organizationId,
    'restaurant_id': restaurantId,
    'branch_id': branchId,
    'device_id': deviceId,
    if (restaurantName != null) 'restaurant_name': restaurantName,
    if (branchName != null) 'branch_name': branchName,
    if (stationName != null) 'station_name': stationName,
    if (employeeProfileId != null) 'employee_profile_id': employeeProfileId,
    if (employeeDisplayName != null)
      'employee_display_name': employeeDisplayName,
    if (capabilities != null) 'capabilities': capabilities,
    'menu': encodePosMenuData(menu),
    if (tax != null)
      'tax': <String, Object?>{'enabled': tax!.enabled, 'rate_bp': tax!.rateBp},
    if (kitchenMode != null) 'kitchen_mode': kitchenMode!.toJson(),
    if (openShift != null) 'open_shift': openShift!.toJson(),
    'printer_purpose_meta': printerPurposeMeta,
    'fetched_at': fetchedAt.toIso8601String(),
    if (sourceRevision != null) 'source_revision': sourceRevision,
  };

  /// Decodes ONE snapshot. The scope ids, the menu, and the fetch time are
  /// LOAD-BEARING and throw when unusable (the store then reports the
  /// envelope UNREADABLE); every optional capture degrades to null.
  static PosOperationalSnapshot fromJson(Map<String, Object?> json) {
    String requiredId(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('operational snapshot has no $key');
      }
      return value;
    }

    final rawMenu = json['menu'];
    if (rawMenu is! Map) {
      throw const FormatException('operational snapshot has no menu payload');
    }
    final fetchedAt = DateTime.tryParse('${json['fetched_at'] ?? ''}');
    if (fetchedAt == null) {
      throw const FormatException('operational snapshot has no fetch time');
    }
    String? nonEmpty(Object? v) {
      final s = v is String ? v.trim() : null;
      return (s == null || s.isEmpty) ? null : s;
    }

    final rawCapabilities = json['capabilities'];
    final rawTax = json['tax'];
    final taxEnabled = rawTax is Map ? rawTax['enabled'] : null;
    final taxRateBp = rawTax is Map ? rawTax['rate_bp'] : null;
    final rawPurposes = json['printer_purpose_meta'];
    final sourceRevision = json['source_revision'];
    return PosOperationalSnapshot(
      organizationId: requiredId('organization_id'),
      // restaurant_id may legitimately be '' (an unset restaurant scope keys
      // as '' too), so it is read tolerantly rather than via requiredId.
      restaurantId: json['restaurant_id'] is String
          ? json['restaurant_id']! as String
          : '',
      branchId: requiredId('branch_id'),
      deviceId: requiredId('device_id'),
      menu: decodePosMenuData(rawMenu.cast<String, Object?>()),
      fetchedAt: fetchedAt.toUtc(),
      restaurantName: nonEmpty(json['restaurant_name']),
      branchName: nonEmpty(json['branch_name']),
      stationName: nonEmpty(json['station_name']),
      employeeProfileId: nonEmpty(json['employee_profile_id']),
      employeeDisplayName: nonEmpty(json['employee_display_name']),
      capabilities: rawCapabilities is Map
          ? rawCapabilities.cast<String, Object?>()
          : null,
      tax: taxEnabled is bool && taxRateBp is int
          ? BranchTax(enabled: taxEnabled, rateBp: taxRateBp)
          : null,
      kitchenMode: PosSnapshotKitchenMode.tryFromJson(json['kitchen_mode']),
      openShift: PosSnapshotShiftRef.tryFromJson(json['open_shift']),
      printerPurposeMeta: rawPurposes is List ? rawPurposes : const <Object?>[],
      sourceRevision: sourceRevision is int ? sourceRevision : null,
    );
  }
}

/// The typed outcome of reading one scope's snapshot. FAIL CLOSED: only
/// [PosOperationalSnapshotLoaded] may ever be served offline.
sealed class PosOperationalSnapshotReadResult {
  const PosOperationalSnapshotReadResult();
}

/// No snapshot has been captured for this scope (or the stored payload names
/// a DIFFERENT scope — key collisions are impossible by construction, so a
/// mismatched payload is a copy this scope has no right to sell from).
final class PosOperationalSnapshotAbsent
    extends PosOperationalSnapshotReadResult {
  const PosOperationalSnapshotAbsent();
}

/// The stored envelope exists but cannot be trusted (unparseable JSON, an
/// unknown schema version, or a menu this build cannot fully decode). Treated
/// as ABSENT by callers, but the bytes are NEVER auto-deleted — a record we
/// cannot read is not a record we are entitled to destroy, and preserving it
/// keeps the evidence for diagnosis (the parked-carts unreadable idiom).
final class PosOperationalSnapshotUnreadable
    extends PosOperationalSnapshotReadResult {
  const PosOperationalSnapshotUnreadable();
}

/// A valid snapshot for the requested scope.
final class PosOperationalSnapshotLoaded
    extends PosOperationalSnapshotReadResult {
  const PosOperationalSnapshotLoaded(this.snapshot);

  final PosOperationalSnapshot snapshot;
}

/// Reads/writes the operational snapshot of ONE scope.
abstract class PosOperationalSnapshotStore {
  /// Loads [scope]'s snapshot (never throws — every failure is a typed
  /// result, and a load NEVER writes, so unreadable bytes survive verbatim).
  Future<PosOperationalSnapshotReadResult> load(PosSyncScope scope);

  /// Atomically replaces [scope]'s snapshot: the new envelope is serialized
  /// FULLY before the durable store is touched, then written with `setString`
  /// and VERIFIED. Throws [PosPersistenceException] when the write does not
  /// stick — the caller keeps the previous snapshot (the old envelope is
  /// untouched, because `setString` either swaps the whole value or fails).
  Future<void> save(PosSyncScope scope, PosOperationalSnapshot snapshot);
}

/// `shared_preferences`-backed store — ONE schema-versioned envelope per
/// scope: `{"version":1,"snapshot":{...}}`.
///
/// The default provider below constructs this store directly over
/// `SharedPreferences.getInstance()` (resolved lazily per call) instead of an
/// in-memory default overridden in `main.dart`: the offline fallback is only
/// worth anything if it is DURABLE by default, on every platform, without a
/// composition step that could be forgotten. Tests inject their own resolver
/// to exercise refused writes.
class SharedPrefsOperationalSnapshotStore
    implements PosOperationalSnapshotStore {
  SharedPrefsOperationalSnapshotStore({
    Future<SharedPreferences> Function()? prefs,
  }) : _resolvePrefs = prefs ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _resolvePrefs;

  @override
  Future<PosOperationalSnapshotReadResult> load(PosSyncScope scope) async {
    final SharedPreferences prefs;
    try {
      prefs = await _resolvePrefs();
    } catch (_) {
      // No durable store at all reads as ABSENT (fail closed, nothing to
      // preserve).
      return const PosOperationalSnapshotAbsent();
    }
    final raw = prefs.getString(operationalSnapshotStorageKey(scope));
    if (raw == null || raw.isEmpty) {
      return const PosOperationalSnapshotAbsent();
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      return const PosOperationalSnapshotUnreadable();
    }
    if (decoded is! Map) return const PosOperationalSnapshotUnreadable();
    final version = (decoded['version'] as num?)?.toInt();
    if (version != PosOperationalSnapshot.schemaVersion) {
      // FAIL CLOSED: an unknown version must not be guessed at — but the
      // bytes stay on disk for the build that understands them.
      return const PosOperationalSnapshotUnreadable();
    }
    final rawSnapshot = decoded['snapshot'];
    if (rawSnapshot is! Map) return const PosOperationalSnapshotUnreadable();
    final PosOperationalSnapshot snapshot;
    try {
      snapshot = PosOperationalSnapshot.fromJson(
        rawSnapshot.cast<String, Object?>(),
      );
    } catch (_) {
      return const PosOperationalSnapshotUnreadable();
    }
    // The payload must name the scope it was requested for. The key already
    // partitions scopes, so a mismatch here is a copied/tampered envelope —
    // ABSENT, never served, never deleted.
    if (snapshot.organizationId != scope.organizationId ||
        snapshot.restaurantId != scope.restaurantId ||
        snapshot.branchId != scope.branchId ||
        snapshot.deviceId != scope.deviceId) {
      return const PosOperationalSnapshotAbsent();
    }
    return PosOperationalSnapshotLoaded(snapshot);
  }

  @override
  Future<void> save(PosSyncScope scope, PosOperationalSnapshot snapshot) async {
    // A snapshot may only ever be stored under the scope its payload names —
    // refusing here keeps key and payload provably in agreement forever.
    if (snapshot.organizationId != scope.organizationId ||
        snapshot.restaurantId != scope.restaurantId ||
        snapshot.branchId != scope.branchId ||
        snapshot.deviceId != scope.deviceId) {
      throw ArgumentError(
        'operational snapshot payload scope does not match the storage scope',
      );
    }
    // Serialize FIRST: an unencodable snapshot fails before the durable store
    // is touched, leaving the previous envelope intact.
    final payload = jsonEncode(<String, Object?>{
      'version': PosOperationalSnapshot.schemaVersion,
      'snapshot': snapshot.toJson(),
    });
    final prefs = await _resolvePrefs();
    // `setString` returns `Future<bool>` and can report FALSE without
    // throwing — a full disk, a browser refusing localStorage. Treating that
    // as success is how a till believes it can sell offline from a snapshot
    // that was never stored.
    final ok = await prefs.setString(
      operationalSnapshotStorageKey(scope),
      payload,
    );
    if (!ok) {
      throw const PosPersistenceException(
        'operational snapshot could not be persisted',
      );
    }
  }
}

/// The operational-snapshot persistence seam. Durable by default (see
/// [SharedPrefsOperationalSnapshotStore]); tests override it or inject a
/// failing prefs resolver.
final posOperationalSnapshotStoreProvider =
    Provider<PosOperationalSnapshotStore>(
      (ref) => SharedPrefsOperationalSnapshotStore(),
    );

/// Assembles and persists the snapshot from whatever operational context is
/// CURRENTLY available — invoked fire-and-forget from the menu fetch success
/// path, and again (kitchen-mode field only) when a verified mode resolves.
///
/// Every read here is `ref.read` of the value already in hand at that moment
/// (never a watch, never an await on another provider): an optional source
/// that has not resolved stores null and NEVER blocks or fails the menu.
/// Both entry points swallow their own failures with the lifecycle's
/// `_guarded` semantics — a refused write ([PosPersistenceException]) keeps
/// the previous snapshot and surfaces nothing to the cashier.
class OperationalSnapshotWriter {
  OperationalSnapshotWriter(this._ref);

  final Ref _ref;

  /// Captures the full snapshot after a successful menu fetch for [scope].
  Future<void> captureAfterMenuFetch({
    required PosSyncScope scope,
    required PosMenuData menu,
    required DateTime fetchedAt,
  }) async {
    try {
      final snapshot = _assemble(
        scope: scope,
        menu: menu,
        fetchedAt: fetchedAt,
      );
      await _ref
          .read(posOperationalSnapshotStoreProvider)
          .save(scope, snapshot);
    } catch (_) {
      // _guarded semantics: a failed snapshot write must never fail the menu
      // load that triggered it; the previous envelope stays authoritative.
    }
  }

  /// Read-modify-swap of ONLY the kitchen-mode capture, when a verified mode
  /// resolves while a snapshot already exists. No snapshot yet => no-op (the
  /// next successful menu fetch captures everything, mode included).
  Future<void> refreshKitchenMode() async {
    try {
      final scope = _ref.read(posSyncScopeProvider);
      if (scope == null) return;
      final mode = PosSnapshotKitchenMode.fromResult(
        _ref.read(posVerifiedKitchenModeProvider),
      );
      if (mode == null) return;
      final store = _ref.read(posOperationalSnapshotStoreProvider);
      final current = await store.load(scope);
      if (current is! PosOperationalSnapshotLoaded) return;
      await store.save(scope, current.snapshot.withKitchenMode(mode));
    } catch (_) {
      // Same containment as above — the mode refresh is an enhancement.
    }
  }

  PosOperationalSnapshot _assemble({
    required PosSyncScope scope,
    required PosMenuData menu,
    required DateTime fetchedAt,
  }) {
    // Display identity — the SAME already-loaded sources the top bar reads
    // (posRestaurantNameProvider / the printer-assignments snapshot); never a
    // fresh fetch, never an invented placeholder.
    final assignments = switch (_ref
        .read(posPrinterAssignmentsProvider)
        .valueOrNull) {
      Success(:final value) => value,
      _ => null,
    };
    String? nonEmpty(String? v) {
      final s = v?.trim();
      return (s == null || s.isEmpty) ? null : s;
    }

    final capabilities = _ref.read(staffCapabilitiesProvider).valueOrNull;
    final shift = _ref.read(posOpenShiftProvider);
    return PosOperationalSnapshot(
      organizationId: scope.organizationId,
      restaurantId: scope.restaurantId,
      branchId: scope.branchId,
      deviceId: scope.deviceId,
      menu: menu,
      fetchedAt: fetchedAt,
      restaurantName: _ref.read(posRestaurantNameProvider),
      branchName: nonEmpty(assignments?.branchName),
      stationName: nonEmpty(assignments?.deviceLabel),
      employeeProfileId: _ref.read(posSignedInEmployeeProfileIdProvider),
      employeeDisplayName: _ref.read(posSignedInStaffNameProvider),
      // The SAME wire shape `pin_session_capabilities` serves, so a later
      // restore can feed the existing parser. Booleans + role only.
      capabilities: capabilities == null
          ? null
          : <String, Object?>{
              'apply_discount': capabilities.applyDiscount,
              'apply_full_comp': capabilities.applyFullComp,
              'manage_menu_availability': capabilities.manageMenuAvailability,
              'manage_table_operations': capabilities.manageTableOperations,
              if (capabilities.role != null) 'role': capabilities.role,
            },
      tax: _ref.read(posBranchTaxProvider).valueOrNull,
      kitchenMode: PosSnapshotKitchenMode.fromResult(
        _ref.read(posVerifiedKitchenModeProvider),
      ),
      openShift: shift == null
          ? null
          : PosSnapshotShiftRef(id: shift.shiftId, openedAt: shift.openedAt),
      // Purpose slots only — endpoints already persist through their own
      // stores and are deliberately not duplicated here.
      printerPurposeMeta: assignments == null
          ? const <Object?>[]
          : <Object?>[
              for (final printer in assignments.printers)
                <String, Object?>{
                  'id': printer.id,
                  'role': printer.role,
                  if (printer.configuredRole != null)
                    'configured_role': printer.configuredRole,
                  'supported_purposes': printer.supportedPurposes,
                  'is_enabled': printer.isEnabled,
                },
            ],
    );
  }
}

/// The snapshot writer seam (root service — no autoDispose).
final operationalSnapshotWriterProvider = Provider<OperationalSnapshotWriter>(
  OperationalSnapshotWriter.new,
);
