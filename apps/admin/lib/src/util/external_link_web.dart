// dart:html is the only no-dependency browser path (package:web would add a
// pubspec dep) — same trade-off as the POS/KDS browser print launchers.
// ignore: deprecated_member_use
import 'dart:html' as html;

/// Opens [url] in a new browser tab.
void openExternalUrl(String url) {
  html.window.open(url, '_blank');
}
