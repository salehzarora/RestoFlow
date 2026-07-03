/// The storage seam for menu images (RF-110 `menu-images` bucket).
///
/// RF-111 defined this interface (with a fake) while both prerequisites were
/// missing; the menu/media sprint closed them — the dashboard has a real
/// authenticated session (RF-151/152) and `menu_items.image_path` is the
/// durable "current image of an item" pointer — so the dashboard now injects a
/// real implementation over `SupabaseClient.storage` and the item editor
/// uploads for real. The demo surface injects [FakeMenuImageStorage] with an
/// explicit demo label (never a fake "uploaded to a server" claim).
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

  /// Deletes the object at [objectKey]. Best-effort at the call sites: a
  /// remove after the pointer was already cleared may fail without harming
  /// correctness (an orphaned blob is unreachable through the app).
  Future<void> remove(String objectKey);
}

/// An in-memory fake for tests AND the labelled demo surface: records uploads
/// and removals and returns a synthetic signed URL. It performs NO real I/O and
/// makes no production persistence claim (the demo panel says so explicitly).
class FakeMenuImageStorage implements MenuImageStorage {
  final List<MenuImageUpload> uploads = [];
  final List<String> removals = [];

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

  @override
  Future<void> remove(String objectKey) async {
    removals.add(objectKey);
  }
}

/// How the image panel talks to storage: the backend + an honest demo flag.
///
/// * `null` (the provider default) — no storage is wired for this surface;
///   the panel shows the honest "upload not available" state.
/// * [isDemo] true — the demo surface: picking/preview work, the (fake) upload
///   is recorded in memory, and the panel shows a clear "demo — not uploaded
///   to a server" note. Never a false persistence claim.
class MenuImageStorageConfig {
  const MenuImageStorageConfig({required this.storage, this.isDemo = false});

  final MenuImageStorage storage;
  final bool isDemo;
}
