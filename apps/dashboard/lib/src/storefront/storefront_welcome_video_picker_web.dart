import 'dart:async';
import 'dart:js_interop';

import 'storefront_welcome_video_file.dart';
import 'storefront_welcome_video_models.dart';

@JS('document.createElement')
external _Input _createInput(JSString tag);
@JS('window.open')
external JSAny? _open(JSString url, JSString target, JSString features);

extension type _Input(JSObject _) implements JSObject {
  external set type(String value);
  external set accept(String value);
  external set multiple(bool value);
  external _Files? get files;
  external void addEventListener(String type, JSFunction listener);
  external void removeEventListener(String type, JSFunction listener);
  external void click();
}
extension type _Files(JSObject _) implements JSObject {
  external int get length;
  external _File? item(int index);
}
extension type _File(JSObject _) implements JSObject {
  external int get size;
  external String get type;
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

const welcomeVideoPickerSupported = true;
const welcomeVideoLinkSupported = true;

/// The size check precedes arrayBuffer: an oversized file is never read into
/// memory. MIME is only a local convenience; Edge validates actual MP4/codecs.
Future<PickedWelcomeVideo?> pickWelcomeVideoFile() {
  final input = _createInput('input'.toJS)
    ..type = 'file'
    ..accept = 'video/mp4,.mp4'
    ..multiple = false;
  final result = Completer<PickedWelcomeVideo?>();
  late JSFunction changed, canceled;
  void detach() {
    input.removeEventListener('change', changed);
    input.removeEventListener('cancel', canceled);
  }

  void complete(PickedWelcomeVideo? value) {
    if (result.isCompleted) return;
    detach();
    result.complete(value);
  }

  void fail(Object error) {
    if (result.isCompleted) return;
    detach();
    result.completeError(error);
  }

  changed = ((JSAny? _) {
    final files = input.files;
    final file = files == null || files.length == 0 ? null : files.item(0);
    if (file == null) {
      complete(null);
      return;
    }
    if (file.size < 1 ||
        file.size > welcomeVideoMaxBytes ||
        file.type.toLowerCase() != 'video/mp4') {
      fail(
        const FormatException('MP4 video must be between 1 byte and 20 MiB'),
      );
      return;
    }
    file.arrayBuffer().toDart.then(
      (buffer) {
        final bytes = buffer.toDart.asUint8List();
        if (bytes.length != file.size || bytes.length > welcomeVideoMaxBytes) {
          fail(const FormatException('incomplete video file'));
        } else {
          complete(PickedWelcomeVideo(bytes: bytes, mimeType: 'video/mp4'));
        }
      },
      onError: (Object error) =>
          fail(const FormatException('video file could not be read')),
    );
  }).toJS;
  canceled = ((JSAny? _) => complete(null)).toJS;
  input.addEventListener('change', changed);
  input.addEventListener('cancel', canceled);
  input.click();
  return result.future;
}

/// Explicit user navigation to an already-published public resource. No
/// embedded player, autoplay, session bridge, CSP relaxation or private URL.
void openPublishedWelcomeVideo(Uri uri) {
  if (uri.scheme != 'https' &&
      !(uri.scheme == 'http' &&
          const ['127.0.0.1', 'localhost'].contains(uri.host)))
    return;
  if (!uri.path.startsWith(
        '/storage/v1/object/public/$welcomeVideoPublicBucket/',
      ) ||
      uri.hasQuery ||
      uri.hasFragment)
    return;
  _open(uri.toString().toJS, '_blank'.toJS, 'noopener,noreferrer'.toJS);
}
