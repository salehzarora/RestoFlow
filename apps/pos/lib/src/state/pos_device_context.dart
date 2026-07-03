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
final posDeviceContextProvider =
    NotifierProvider<PosDeviceContextController, DeviceContext?>(
      PosDeviceContextController.new,
    );

class PosDeviceContextController extends Notifier<DeviceContext?> {
  @override
  DeviceContext? build() => null;

  /// Publishes the gate's current device (null when unpaired/cleared).
  void set(DeviceContext? device) => state = device;
}
