// dart:html is the only no-dependency browser path (package:web would add a
// pubspec dep) — the same trade-off as the print launchers.
// ignore: deprecated_member_use
import 'dart:html' as html;

/// Rewrites the address bar to [cleaned] WITHOUT adding a history entry.
///
/// `replaceState`, never a navigation: a recovery link must not survive in
/// history, where a back button — or anyone with the machine — could replay it.
void replaceBrowserUrl(Uri cleaned) {
  html.window.history.replaceState(null, '', cleaned.toString());
}
