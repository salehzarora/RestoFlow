import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

/// The paired device context of THIS KDS station, published by the pairing
/// gate (device settings sprint).
///
/// The gate owns pairing/restore; this provider only MIRRORS the resulting
/// [DeviceContext] so operational surfaces below it (the ⋮ device-settings
/// sheet, including the LIVE board that renders without the gate in its
/// tree) can show what device they are running on. Null = demo mode / not
/// paired / restore pending. Carries ids + display data only — never the
/// device session token (that stays in the secure store, RF-161) and never
/// money (T-003).
final kdsDeviceContextProvider =
    NotifierProvider<KdsDeviceContextController, DeviceContext?>(
      KdsDeviceContextController.new,
    );

class KdsDeviceContextController extends Notifier<DeviceContext?> {
  @override
  DeviceContext? build() => null;

  /// Publishes the gate's current device (null when unpaired/cleared).
  void set(DeviceContext? device) => state = device;
}
