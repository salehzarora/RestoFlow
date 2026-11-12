import 'package:flutter/material.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'storefront_copy.dart';
import 'storefront_banner_preview_geometry.dart';

/// Native/widget tests do not pretend to reproduce a browser's font layout.
class StorefrontBannerPreviewFrame extends StatelessWidget {
  const StorefrontBannerPreviewFrame({
    required this.data,
    required this.focalX,
    required this.focalY,
    required this.logicalWidth,
    required this.onCrop,
    super.key,
  });
  final Map<String, Object?> data;
  final int focalX, focalY;
  final double logicalWidth;
  final ValueChanged<StorefrontBannerCrop> onCrop;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(
      storefrontContentCopy(AppLocalizations.of(context), 'bannerWebOnly'),
    ),
  );
}
