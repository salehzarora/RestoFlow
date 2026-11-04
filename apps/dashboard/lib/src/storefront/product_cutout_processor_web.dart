import 'dart:js_interop';
import 'dart:typed_data';
import 'product_cutout_processor.dart';

@JS('bizbotProductCutout.process')
external JSPromise<_Result> _process(
  JSUint8Array bytes,
  JSString mimeType,
  JSFunction progress,
  JSString owner,
);
@JS('bizbotProductCutout.cancel')
external void _cancel(JSString owner);

extension type _Result(JSObject _) implements JSObject {
  external JSUint8Array get bytes;
  external JSString get mimeType;
  external JSNumber get width;
  external JSNumber get height;
  external JSBoolean get alreadyTransparent;
}

ProductCutoutProcessor createProcessor() => _BrowserProcessor();

class _BrowserProcessor implements ProductCutoutProcessor {
  late final String _owner = 'product-cutout-${identityHashCode(this)}';
  @override
  Future<ProductCutoutCandidate> process(
    Uint8List bytes,
    String mimeType, {
    void Function(String stage)? onProgress,
  }) async {
    final result = await _process(
      bytes.toJS,
      mimeType.toJS,
      ((JSString stage) => onProgress?.call(stage.toDart)).toJS,
      _owner.toJS,
    ).toDart;
    return ProductCutoutCandidate(
      bytes: result.bytes.toDart,
      mimeType: result.mimeType.toDart,
      width: result.width.toDartInt,
      height: result.height.toDartInt,
      alreadyTransparent: result.alreadyTransparent.toDart,
    );
  }

  @override
  void cancel() => _cancel(_owner.toJS);
}
