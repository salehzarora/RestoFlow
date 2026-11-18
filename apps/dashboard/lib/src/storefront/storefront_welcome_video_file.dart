import 'dart:typed_data';

class PickedWelcomeVideo {
  const PickedWelcomeVideo({required this.bytes, required this.mimeType});
  final Uint8List bytes;
  final String mimeType;
}
