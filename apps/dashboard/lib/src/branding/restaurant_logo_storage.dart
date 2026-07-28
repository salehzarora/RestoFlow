import 'dart:typed_data';

import 'package:supabase/supabase.dart';

import 'restaurant_logo_path.dart';

/// PRINT-BRANDING-LOGO-001 — the restaurant-logo blob store seam.
///
/// Reads are signed URLs ONLY (private bucket — D-032; never `getPublicUrl`).
/// Every operation THROWS on failure so the workflow surfaces an honest error
/// and never claims success first (the atomic upload-then-pointer flow depends
/// on it). Authorization is server-side via the restaurant_logos storage
/// policies (owner/manager writes; no service-role key — D-011).
abstract interface class RestaurantLogoStorage {
  Future<void> upload({
    required String objectKey,
    required Uint8List bytes,
    required String mimeType,
  });

  Future<Uri> createSignedUrl(
    String objectKey, {
    Duration expiresIn = const Duration(minutes: 30),
  });

  Future<void> remove(String objectKey);
}

/// The real [RestaurantLogoStorage] over the dashboard's single authenticated
/// anon-key [SupabaseClient] (D-011). Mirrors SupabaseMenuImageStorage.
class SupabaseRestaurantLogoStorage implements RestaurantLogoStorage {
  SupabaseRestaurantLogoStorage(this._client);

  final SupabaseClient _client;

  StorageFileApi get _bucket => _client.storage.from(kRestaurantLogosBucketId);

  @override
  Future<void> upload({
    required String objectKey,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    await _bucket.uploadBinary(
      objectKey,
      bytes,
      fileOptions: FileOptions(contentType: mimeType, upsert: true),
    );
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
