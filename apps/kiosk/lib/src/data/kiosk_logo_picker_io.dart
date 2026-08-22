import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Android/iOS/desktop: the platform photo picker via `image_picker` (the
/// modern Android Photo Picker needs no storage permission). Bytes only —
/// no path is retained or logged.
const bool kioskLogoPickerSupported = true;

Future<Uint8List?> pickKioskLogoBytes() async {
  final XFile? file;
  try {
    file = await ImagePicker().pickImage(source: ImageSource.gallery);
  } catch (_) {
    return null; // no picker on this platform/session — honest null
  }
  if (file == null) return null;
  try {
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}
