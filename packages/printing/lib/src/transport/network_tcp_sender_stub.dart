import 'dart:typed_data';

import '../print_result.dart';

/// Web / non-`dart:io` fallback for [sendEscPosOverTcp] (ANDROID-002).
///
/// A browser cannot open a raw TCP socket, so this fails clearly rather than
/// pretending to print. The native (`dart:io`) implementation in
/// `network_tcp_sender_io.dart` is selected by a conditional import on any
/// platform that has `dart.library.io` (Android/iOS/desktop). This keeps the
/// pure-Dart printing package web-safe: web never links `dart:io`.
Future<PrintResult> sendEscPosOverTcp({
  required String host,
  required int port,
  required Uint8List bytes,
  required Duration timeout,
}) async {
  return const PrintResult.failure(
    PrinterErrorCategory.unsupported,
    'Network (TCP) printing is not available on this platform. Use the print '
    'bridge on web; direct network printing needs the native app.',
  );
}
