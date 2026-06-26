/// The (deferred) storage seam for menu images (RF-110 `menu-images` bucket).
///
/// RF-111 defines this interface and a fake, plus the path/validation helpers,
/// but does NOT wire production upload/signed-URL behaviour, because:
///   * D1 — there is no authenticated Supabase session yet, so the RF-110
///     storage policies (`auth.uid()` -> membership) cannot pass; and
///   * D2 / D-032 — there is no backend pointer for the "current image of an
///     item", so a real upload could not be durably associated with the item.
/// The UI therefore shows a clearly-labelled deferred image panel rather than a
/// fake "image saved" experience. The real implementation (needing an
/// authenticated `SupabaseClient.storage`) lands once those prerequisites exist.
library;

/// The outcome of a (future) menu image upload.
class MenuImageUpload {
  const MenuImageUpload({required this.objectKey});

  /// The RF-110 storage object key the image was written to.
  final String objectKey;
}

/// A menu image storage backend. Reads of the private bucket use a signed URL
/// (`createSignedUrl`) — there is NO public URL (DECISION D-032).
abstract class MenuImageStorage {
  /// Uploads image [bytes] of [mimeType] to [objectKey] in the `menu-images`
  /// bucket. Subject to the RF-110 write policy (owner/manager; item must exist).
  Future<MenuImageUpload> upload({
    required String objectKey,
    required List<int> bytes,
    required String mimeType,
  });

  /// Returns a short-lived signed URL for a private object the SELECT policy
  /// permits. There is no durable/public URL for the private bucket.
  Future<Uri> createSignedUrl(
    String objectKey, {
    Duration expiresIn = const Duration(minutes: 30),
  });
}

/// An in-memory fake for tests: records uploads and returns a synthetic signed
/// URL. It performs NO real I/O and makes no production persistence claim.
class FakeMenuImageStorage implements MenuImageStorage {
  final List<MenuImageUpload> uploads = [];

  @override
  Future<MenuImageUpload> upload({
    required String objectKey,
    required List<int> bytes,
    required String mimeType,
  }) async {
    final upload = MenuImageUpload(objectKey: objectKey);
    uploads.add(upload);
    return upload;
  }

  @override
  Future<Uri> createSignedUrl(
    String objectKey, {
    Duration expiresIn = const Duration(minutes: 30),
  }) async {
    return Uri.parse('fake-signed://menu-images/$objectKey');
  }
}
