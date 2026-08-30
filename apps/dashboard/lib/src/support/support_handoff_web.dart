// dart:html is the only no-dependency browser path (package:web would add a
// pubspec dep) — the same trade-off as the print launchers.
// ignore: deprecated_member_use
import 'dart:html' as html;

import 'platform_support.dart';

/// Reads the one-time support handoff from the URL fragment and REMOVES it.
///
/// `replaceState` rather than a navigation: the token must leave the address
/// bar without adding a history entry that still contains it. The fragment is
/// never transmitted, so this is defence against a shoulder-surfed URL or a
/// copied link, not against the network.
String? takeSupportHandoff() =>
    takeSupportHandoffToken(html.window.location.hash, (cleaned) {
      // An empty remainder drops the `#` entirely rather than leaving a bare
      // one behind, so a support launch and an ordinary one end up at the same
      // URL and neither looks special afterwards.
      final base = Uri.base.removeFragment();
      final url = cleaned.isEmpty
          ? base.toString()
          : base.replace(fragment: cleaned).toString();
      html.window.history.replaceState(null, '', url);
    });
