import 'dart:typed_data';
import 'product_cutout_processor.dart';

ProductCutoutProcessor createProcessor() => _Unsupported();

class _Unsupported implements ProductCutoutProcessor {
  @override
  Future<ProductCutoutCandidate> process(
    Uint8List bytes,
    String mimeType, {
    void Function(String stage)? onProgress,
  }) => Future.error(
    StateError('Local background removal requires the web Dashboard.'),
  );
  @override
  void cancel() {}
}
