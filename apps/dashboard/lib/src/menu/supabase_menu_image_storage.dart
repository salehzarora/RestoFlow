import 'dart:typed_data';

import 'package:restoflow_feature_menu/restoflow_feature_menu.dart'
    show MenuImageStorage, MenuImageUpload, kMenuImagesBucketId;
import 'package:supabase/supabase.dart';

/// The REAL [MenuImageStorage] (menu/media sprint): the RF-110 private
/// `menu-images` bucket over the dashboard's single authenticated anon-key
/// [SupabaseClient] (DECISION D-011 — no service-role key; the GoTrue session
/// carries the caller's identity, and the RF-110 storage.objects policies do
/// the authorization server-side: owner/manager writes, membership reads).
///
/// Reads are signed URLs ONLY (private bucket — D-032; never `getPublicUrl`).
/// Every operation throws on failure — callers surface an honest error and
/// never claim success first.
class SupabaseMenuImageStorage implements MenuImageStorage {
  SupabaseMenuImageStorage(this._client);

  final SupabaseClient _client;

  StorageFileApi get _bucket => _client.storage.from(kMenuImagesBucketId);

  @override
  Future<MenuImageUpload> upload({
    required String objectKey,
    required List<int> bytes,
    required String mimeType,
  }) async {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    await _bucket.uploadBinary(
      objectKey,
      data,
      fileOptions: FileOptions(contentType: mimeType, upsert: true),
    );
    return MenuImageUpload(objectKey: objectKey);
  }

  @override
  Future<Uri> createSignedUrl(
    String objectKey, {
    Duration expiresIn = const Duration(minutes: 30),
  }) async {
    final url = await _bucket.createSignedUrl(objectKey, expiresIn.inSeconds);
    return Uri.parse(url);
  }

  @override
  Future<void> remove(String objectKey) async {
    await _bucket.remove([objectKey]);
  }
}
