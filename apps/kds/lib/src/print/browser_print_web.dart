// Browser-print launcher — web target (RF-118). Only compiled for the web build
// (selected via the conditional import in `browser_print.dart`), so `dart:html`
// never reaches Windows/desktop/mobile/test builds. dart:html is the only
// no-dependency browser-print path (package:web would add a pubspec dep).
// ignore_for_file: deprecated_member_use
import 'dart:html' as html;

/// Triggers the browser's native print dialog (which prints the current page,
/// showing the print-preview overlay). This is a real browser print — NOT a
/// hardware-printer integration.
void launchBrowserPrint() {
  html.window.print();
}
