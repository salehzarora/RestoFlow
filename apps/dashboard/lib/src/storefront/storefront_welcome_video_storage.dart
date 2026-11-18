import 'dart:typed_data';

/// A narrow capability of the existing signed-in user's client. It provides
/// no session/client/key getter and cannot publish, select or delete an asset.
abstract interface class StorefrontWelcomeVideoStorage {
  Future<void> uploadWelcomeVideo({
    required String objectKey,
    required Uint8List bytes,
  });
  Uri publicWelcomeVideoUrl(String objectKey);
}
