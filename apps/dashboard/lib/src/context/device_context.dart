import 'package:flutter/foundation.dart';

/// A device/station pairing context, scoped to a selected organization + branch
/// (RF-152 foundation). Present ONLY when a real device has been paired — this
/// project never fabricates a paired device.
@immutable
class DeviceContext {
  const DeviceContext({
    required this.organizationId,
    required this.branchId,
    this.deviceId,
    this.stationId,
  });

  final String organizationId;
  final String branchId;

  /// The paired device id, or null when no device is paired yet.
  final String? deviceId;

  /// The bound station id, or null.
  final String? stationId;

  /// True only when a real device id is present. RF-152 never sets this (pairing
  /// is deferred to RF-153/RF-154), so it is always false for now.
  bool get isPaired => deviceId != null && deviceId!.isNotEmpty;
}

/// Holds the current [DeviceContext] (RF-152 foundation).
///
/// ABSENT (null) by DEFAULT — RestoFlow never claims a POS/KDS device is paired.
/// Real device pairing UX + persistence are deferred to RF-153/RF-154; this only
/// provides the model + a clearable, org/branch-scoped holder that is CLEARED on
/// sign-out. Kept as a plain [ChangeNotifier] so it is injectable + unit-testable
/// without a backend, and reusable by the later POS/KDS pairing flows.
class DeviceContextController extends ChangeNotifier {
  DeviceContext? _context;

  /// The current device context, or null when no device is paired.
  DeviceContext? get context => _context;

  /// Whether a real device is currently paired (always false until RF-153).
  bool get hasPairedDevice => _context?.isPaired ?? false;

  /// Clears the device context (called on sign-out). No-op when already absent.
  void clear() {
    if (_context == null) return;
    _context = null;
    notifyListeners();
  }
}
