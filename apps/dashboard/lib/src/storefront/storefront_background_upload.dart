import 'package:restoflow_feature_menu/restoflow_feature_menu.dart'
    show PickedMenuImage, menuImagePickerSupported, pickMenuImageFile;

import '../branding/restaurant_logo_path.dart';
import '../branding/restaurant_logo_storage.dart';
import 'storefront_media_publisher.dart';
import 'storefront_models.dart';

/// Uploads an independent private original. It never saves the receipt-logo
/// pointer, assigns a profile slot, or removes a shared image. The existing
/// authenticated publisher validates/derives the bytes after this operation.
class StorefrontBackgroundUpload {
  StorefrontBackgroundUpload({
    required this.storage,
    required this.organizationId,
    required this.restaurantId,
    Future<PickedMenuImage?> Function()? picker,
    bool? pickerSupported,
    LogoImageIdGenerator? ids,
  }) : _picker = picker ?? pickMenuImageFile,
       supported = pickerSupported ?? menuImagePickerSupported,
       _ids = ids ?? RandomLogoImageIdGenerator();

  final RestaurantLogoStorage storage;
  final String organizationId, restaurantId;
  final Future<PickedMenuImage?> Function() _picker;
  final LogoImageIdGenerator _ids;
  final bool supported;

  Future<StorefrontMediaSource?> pickAndUpload({
    required bool Function() isCurrent,
  }) async {
    if (!supported || !isCurrent()) return null;
    final picked = await _picker();
    // A membership switch while the browser dialog is open must not upload
    // through an obsolete authenticated binding.
    if (picked == null || !isCurrent()) return null;
    if (!isAllowedRestaurantLogoMime(picked.mimeType) ||
        !isWithinRestaurantLogoSizeLimit(picked.bytes.length)) {
      throw const FormatException('invalid background image');
    }
    final mime = picked.mimeType.trim().toLowerCase();
    final key = buildRestaurantLogoObjectKey(
      organizationId: organizationId,
      restaurantId: restaurantId,
      imageId: _ids.newImageId(),
      extension: extensionForLogoMime(mime),
    );
    await storage.upload(objectKey: key, bytes: picked.bytes, mimeType: mime);
    if (!isCurrent()) return null;
    return StorefrontMediaSource(
      bucket: StorefrontSourceBucket.restaurantLogos,
      key: key,
    );
  }
}
