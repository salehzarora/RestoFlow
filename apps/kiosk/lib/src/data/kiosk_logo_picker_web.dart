// Zero-dependency browser image-file picker (same pattern as the Dashboard
// menu-image picker). Only compiled for web builds via the conditional
// import in `kiosk_logo_picker.dart`.
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

const bool kioskLogoPickerSupported = true;

Future<Uint8List?> pickKioskLogoBytes() {
  final input = html.FileUploadInputElement()
    ..accept = 'image/png,image/jpeg,image/webp'
    ..multiple = false;
  final completer = Completer<Uint8List?>();

  void complete(Uint8List? value) {
    if (!completer.isCompleted) completer.complete(value);
  }

  input.onChange.first.then((_) {
    final files = input.files;
    if (files == null || files.isEmpty) {
      complete(null);
      return;
    }
    final reader = html.FileReader();
    reader.onLoadEnd.first.then((_) {
      final result = reader.result;
      complete(result is Uint8List ? result : null);
    });
    reader.onError.first.then((_) => complete(null));
    reader.readAsArrayBuffer(files.first);
  });
  input.on['cancel'].first.then((_) => complete(null));
  input.click();
  return completer.future;
}
