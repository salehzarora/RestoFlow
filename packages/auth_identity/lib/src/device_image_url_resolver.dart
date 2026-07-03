/// Minimal signed-URL resolver for DEVICE surfaces (menu/media sprint).
///
/// A paired POS device is an ANONYMOUS authenticated principal (RF-161) with
/// zero tenant authority; its ONLY storage capability is the narrowly-scoped
/// `menu_images_device_select` policy (an ACTIVE, unrevoked, `auth.uid()`-bound
/// POS device session may READ its own org/restaurant menu images). This seam
/// exposes exactly that: batch signed-URL creation for the private RF-110
/// `menu-images` bucket — no upload, no delete, no other bucket, and NOTHING
/// money-bearing. KDS surfaces never receive an instance (T-014).
library;

/// Resolves short-lived signed URLs for menu-image object keys the device's
/// storage policy permits. Keys the policy denies (or that fail) are simply
/// ABSENT from the result — callers fall back to their imageless rendering
/// (fail-soft: menu images are an enhancement, never load-bearing).
abstract class DeviceImageUrlResolver {
  /// Returns `objectKey -> signed URL` for the [objectKeys] that resolved.
  /// Never throws for per-key denials; implementations may throw only on a
  /// transport-level failure (callers treat that as "no images").
  Future<Map<String, String>> signedUrlsFor(
    List<String> objectKeys, {
    Duration expiresIn = const Duration(minutes: 30),
  });
}

/// A test fake: returns a canned map (or throws when [error] is set).
class FakeDeviceImageUrlResolver implements DeviceImageUrlResolver {
  FakeDeviceImageUrlResolver({this.urls = const {}, this.error});

  final Map<String, String> urls;
  final Object? error;
  final List<List<String>> requests = [];

  @override
  Future<Map<String, String>> signedUrlsFor(
    List<String> objectKeys, {
    Duration expiresIn = const Duration(minutes: 30),
  }) async {
    requests.add(List.of(objectKeys));
    final err = error;
    if (err != null) throw err is Exception ? err : Exception(err.toString());
    return {
      for (final key in objectKeys)
        if (urls.containsKey(key)) key: urls[key]!,
    };
  }
}
