import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

/// The paired device context of THIS POS station, published by the pairing
/// gate (device settings sprint).
///
/// The gate owns pairing/restore; this provider only MIRRORS the resulting
/// [DeviceContext] so operational surfaces below it (the ⋮ device-settings
/// sheet) can show what device they are running on without re-threading
/// constructor params. Null = demo mode / not paired / restore pending.
/// Carries ids + display data only — never the device session token (that
/// stays in the secure store, RF-161).
///
/// PRINT-STARTUP-REPRINT-001: `null` here is AMBIGUOUS — it means demo, or
/// unpaired, or *restore still pending*. Device-scoped LOCAL PREFERENCES must
/// never choose a storage namespace from an ambiguous null, so they resolve
/// through [posPrinterScopeProvider] instead of reading this directly.
final posDeviceContextProvider =
    NotifierProvider<PosDeviceContextController, DeviceContext?>(
      PosDeviceContextController.new,
    );

class PosDeviceContextController extends Notifier<DeviceContext?> {
  @override
  DeviceContext? build() => null;

  /// Publishes the gate's current device (null when unpaired/cleared).
  ///
  /// Also ENDS any pending restore: once the gate has published its result the
  /// preference scope is authoritative, whether or not a device was restored.
  void set(DeviceContext? device) {
    state = device;
    ref.read(posDeviceRestorePendingProvider.notifier).end();
  }
}

/// PRINT-STARTUP-REPRINT-001 — is a device-session restore currently in flight?
///
/// Defaults to **false** (resolved) so demo mode, tests, and any composition
/// without a pairing gate resolve IMMEDIATELY to the local namespace and can
/// never wait forever for a device context that will never be published. Only
/// the pairing gate, which is the one component that knows a restore is
/// pending, flips it on — and [PosDeviceContextController.set] flips it off.
final posDeviceRestorePendingProvider =
    NotifierProvider<PosDeviceRestorePendingController, bool>(
      PosDeviceRestorePendingController.new,
    );

/// The pending mark, held OUTSIDE Riverpod.
///
/// The gate must mark a pending publish synchronously from `initState`, before
/// any POS subtree can build and resolve a printer scope — but writing to a
/// provider while the tree is building is illegal (the same rule the gate's
/// `_publish` already defers around). So the mark is a plain flag that
/// [PosDeviceRestorePendingController.build] reads as its initial value, and
/// only the ENDING transition (always async: a post-frame publish or a restore
/// completing) goes through the provider.
bool _posDeviceRestorePendingSeed = false;

/// Marks a device-context publish as pending. Safe to call from `initState`.
void markPosDeviceRestorePending() => _posDeviceRestorePendingSeed = true;

/// Clears the mark without touching a provider — for a gate disposed before it
/// ever published, so a pending mark can never leak into the next composition.
void clearPosDeviceRestorePendingMark() => _posDeviceRestorePendingSeed = false;

class PosDeviceRestorePendingController extends Notifier<bool> {
  @override
  bool build() => _posDeviceRestorePendingSeed;

  /// Marks a device-context publish as pending (the gate is restoring, or is
  /// about to publish an injected initial device). Preference providers then
  /// WAIT instead of resolving to the legacy local namespace.
  void begin() {
    markPosDeviceRestorePending();
    state = true;
  }

  /// Marks the restore finished (the gate published its result).
  void end() {
    clearPosDeviceRestorePendingMark();
    state = false;
  }
}

/// The stable key segment used when there is definitively no paired device
/// (demo / not yet paired). Kept in one place so every preference family agrees.
const String kPosPrinterScopeLocalKey = 'local';

/// PRINT-STARTUP-REPRINT-001 — the authoritative namespace a device-scoped POS
/// preference belongs to.
///
/// Three states, deliberately distinguishable:
///  * **unresolved** — a device-context publish is pending; NOTHING may be read
///    or written yet (a transient null is NOT "local").
///  * **device** — a real paired device id.
///  * **local** — definitively demo / unpaired.
class PosPrinterScope {
  const PosPrinterScope._(this.resolved, this.deviceId);

  /// Restore pending — not safe to pick a namespace yet.
  const PosPrinterScope.unresolved() : this._(false, null);

  /// Definitively demo / unpaired: the legacy local namespace.
  const PosPrinterScope.local() : this._(true, null);

  /// A real paired device namespace.
  const PosPrinterScope.device(String deviceId) : this._(true, deviceId);

  final bool resolved;
  final String? deviceId;

  /// The `shared_preferences` key segment, or null while unresolved.
  String? get keySegment =>
      resolved ? (deviceId ?? kPosPrinterScopeLocalKey) : null;

  /// True when this is a real device namespace (not demo/unpaired).
  bool get isDevice => resolved && deviceId != null;

  @override
  bool operator ==(Object other) =>
      other is PosPrinterScope &&
      other.resolved == resolved &&
      other.deviceId == deviceId;

  @override
  int get hashCode => Object.hash(resolved, deviceId);

  @override
  String toString() => resolved
      ? 'PosPrinterScope.${deviceId == null ? 'local' : 'device($deviceId)'}'
      : 'PosPrinterScope.unresolved';
}

/// The resolved preference scope for THIS station.
///
/// A published device always wins (so an injected/seeded context resolves
/// immediately). Otherwise the scope is LOCAL unless a restore is pending, in
/// which case it stays UNRESOLVED until the gate publishes. No timers, no
/// post-frame assumptions — purely the pairing gate's own signal.
final posPrinterScopeProvider = Provider<PosPrinterScope>((ref) {
  final device = ref.watch(posDeviceContextProvider);
  final id = device?.deviceId;
  if (id != null && id.isNotEmpty) return PosPrinterScope.device(id);
  return ref.watch(posDeviceRestorePendingProvider)
      ? const PosPrinterScope.unresolved()
      : const PosPrinterScope.local();
});

/// The authoritative key segment, available only once the scope RESOLVES.
///
/// While the scope is unresolved this future deliberately never completes: the
/// dependent provider stays in its loading state and is re-built (superseding
/// this future) the moment the scope resolves. That is what makes a cold
/// paired startup WAIT instead of reading the legacy local namespace.
final posPrinterScopeSegmentProvider = FutureProvider<String>((ref) {
  final scope = ref.watch(posPrinterScopeProvider);
  final segment = scope.keySegment;
  if (segment != null) return Future<String>.value(segment);
  return Completer<String>().future; // superseded on resolution
});

/// The device-session manager for THIS POS (device settings sprint, Part G),
/// used ONLY for the staff-safe "Unpair this device" control: it clears the
/// local device session (and best-effort server self-revoke — the existing,
/// intended [DeviceSessionManager.unpair]). Null in demo / unconfigured real
/// mode (the Unpair control is then hidden — no owner/admin capability is
/// ever exposed). Overridden in `main.dart` with the paired-device repo.
final posDeviceSessionManagerProvider = Provider<DeviceSessionManager?>(
  (ref) => null,
);
