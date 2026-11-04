import 'dart:typed_data';

import 'package:restoflow_feature_menu/restoflow_feature_menu.dart';

/// Private original and server-proven generation, captured before processing.
class ProductCutoutOriginal {
  const ProductCutoutOriginal({
    required this.bytes,
    required this.mimeType,
    required this.sourceKey,
    required this.sourceGeneration,
  });
  final Uint8List bytes;
  final String mimeType;
  final String sourceKey;
  final String sourceGeneration;
}

enum ProductCutoutPublishStatus {
  published,
  uncertain,
  staleSource,
  denied,
  unavailable,
}

class ProductCutoutPublishResult {
  const ProductCutoutPublishResult(this.status);
  final ProductCutoutPublishStatus status;
}

/// Dashboard-only seam. Candidate bytes stay private until the existing
/// authorized publication flow validates ownership and source generation.
abstract interface class ProductCutoutGateway {
  Future<ProductCutoutOriginal> loadOriginal(MenuItem item);

  /// null candidate selects Original. Implementations MUST NOT change the
  /// menu image pointer or overwrite the original. Retry uses the same id.
  Future<ProductCutoutPublishResult> publish({
    required MenuItem item,
    required ProductCutoutOriginal original,
    required String requestId,
    Uint8List? candidateBytes,
    String? candidateMimeType,
  });
}
