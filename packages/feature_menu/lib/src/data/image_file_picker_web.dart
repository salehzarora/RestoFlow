// Zero-dependency browser image-file picker — web target only (menu/media
// sprint). Only compiled for web builds (selected via the conditional export
// in `image_file_picker.dart`), so `dart:html` never reaches desktop/mobile/
// test builds. dart:html is the only no-dependency browser path (`package:web`
// would add a pubspec dependency).
// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

import 'menu_image_path.dart';
import 'picked_menu_image.dart';

/// The web build has a real `<input type="file">` picker.
const bool menuImagePickerSupported = true;

/// Opens the browser file picker restricted to the RF-110 image MIME types and
/// resolves with the picked file's bytes, or null when the user cancels (or the
/// file cannot be read). Nothing is uploaded here — the caller validates,
/// previews, and uploads only on an explicit confirm.
Future<PickedMenuImage?> pickMenuImageFile() {
  final input = html.FileUploadInputElement()
    ..accept = kAllowedMenuImageMimeTypes.join(',')
    ..multiple = false;
  final completer = Completer<PickedMenuImage?>();

  void complete(PickedMenuImage? value) {
    if (!completer.isCompleted) completer.complete(value);
  }

  input.onChange.first.then((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      complete(null);
      return;
    }
    final file = files.first;
    final reader = html.FileReader();
    reader.onLoadEnd.first.then((_) {
      final result = reader.result;
      if (result is Uint8List) {
        complete(
          PickedMenuImage(
            bytes: result,
            mimeType: file.type,
            fileName: file.name,
          ),
        );
      } else {
        complete(null); // unreadable file — never a fake pick
      }
    });
    reader.onError.first.then((_) => complete(null));
    reader.readAsArrayBuffer(file);
  });
  // Modern browsers fire 'cancel' on the input when the dialog is dismissed;
  // where unsupported the future simply stays pending until a file is chosen
  // (the panel keeps its normal idle UI — no spinner is tied to the picker).
  input.on['cancel'].first.then((_) => complete(null));

  input.click();
  return completer.future;
}
