import 'dart:async';

import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

import 'pos_media_image.dart';

/// Both explicit settings unpair and local repair forget the device's media.
void clearPosPairingMedia(DeviceImageUrlResolver? resolver) {
  if (resolver is CachingDeviceImageUrlResolver) resolver.clear();
  unawaited(PosMediaCache.clearIfCreated());
}
