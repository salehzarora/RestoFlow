import 'dart:typed_data';

import 'product_cutout_processor_stub.dart'
    if (dart.library.js_interop) 'product_cutout_processor_web.dart'
    as platform;

class ProductCutoutCandidate {
  const ProductCutoutCandidate({
    required this.bytes,
    required this.mimeType,
    required this.width,
    required this.height,
    this.alreadyTransparent = false,
  });
  final Uint8List bytes;
  final String mimeType;
  final int width;
  final int height;
  final bool alreadyTransparent;
}

abstract interface class ProductCutoutProcessor {
  Future<ProductCutoutCandidate> process(
    Uint8List bytes,
    String mimeType, {
    void Function(String stage)? onProgress,
  });
  void cancel();
}

ProductCutoutProcessor createProductCutoutProcessor() =>
    platform.createProcessor();
