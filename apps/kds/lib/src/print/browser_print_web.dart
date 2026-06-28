// Isolated browser-print launcher — web target (RF-118). Only compiled for the
// web build (selected via the conditional export in `browser_print.dart`), so
// `dart:html` never reaches Windows/desktop/mobile/test builds. dart:html is the
// only no-dependency browser path (package:web would add a pubspec dep).
// ignore_for_file: deprecated_member_use
import 'dart:html' as html;

/// Opens [htmlContent] as an ISOLATED document in a new browser window/tab via a
/// blob URL, and lets that document print itself (its onload script calls
/// window.print(), and closes after). Only the kitchen-ticket page is printed —
/// NOT the Flutter KDS board behind the modal. This is a real browser print, not
/// a hardware-printer integration.
void printHtmlDocument(String htmlContent, String title) {
  final blob = html.Blob(<Object>[htmlContent], 'text/html');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
}
