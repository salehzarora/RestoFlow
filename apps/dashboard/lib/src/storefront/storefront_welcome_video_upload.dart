import 'dart:typed_data';

import 'storefront_welcome_video_file.dart';
import 'storefront_welcome_video_models.dart';
import 'storefront_welcome_video_picker.dart';
import 'storefront_welcome_video_storage.dart';

class StorefrontWelcomeVideoUpload {
  StorefrontWelcomeVideoUpload({
    required this.storage,
    required this.organizationId,
    required this.restaurantId,
    Future<PickedWelcomeVideo?> Function()? picker,
    bool? pickerSupported,
    String Function()? ids,
  }) : _picker = picker ?? pickWelcomeVideoFile,
       supported = pickerSupported ?? welcomeVideoPickerSupported,
       _ids = ids ?? newWelcomeVideoId;

  final StorefrontWelcomeVideoStorage storage;
  final String organizationId, restaurantId;
  final bool supported;
  final Future<PickedWelcomeVideo?> Function() _picker;
  final String Function() _ids;

  Future<String?> pickAndUpload({required bool Function() isCurrent}) async {
    if (!supported || !isCurrent()) return null;
    final file = await _picker();
    if (file == null || !isCurrent()) return null;
    if (file.mimeType.trim().toLowerCase() != 'video/mp4' ||
        file.bytes.isEmpty ||
        file.bytes.length > welcomeVideoMaxBytes) {
      throw const FormatException('invalid welcome video');
    }
    final id = _ids();
    final key = '$organizationId/$restaurantId/$id.mp4';
    if (!welcomeVideoSourceBelongsTo(key, organizationId, restaurantId)) {
      throw const FormatException('invalid welcome video scope');
    }
    await storage.uploadWelcomeVideo(
      objectKey: key,
      bytes: Uint8List.fromList(file.bytes),
    );
    return isCurrent() ? key : null;
  }
}
