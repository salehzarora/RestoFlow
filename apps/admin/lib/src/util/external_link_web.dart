// dart:html is the only no-dependency browser path (package:web would add a
// pubspec dep) — same trade-off as the POS/KDS browser print launchers.
// ignore: deprecated_member_use
import 'dart:html' as html;

/// Opens [url] in a new browser tab with NO usable opener on the new tab.
///
/// ADMIN-126B2 (reverse-tabnabbing): the support handoff opens a CROSS-ORIGIN
/// Dashboard tab. Without protection that tab receives a live `window.opener`
/// reference back to the admin console and could navigate it away. Passing the
/// standard `noopener,noreferrer` window feature severs that reference (the
/// spec makes `window.open` return null and leaves the new context with a null
/// `opener`) and, via `noreferrer`, keeps the admin origin out of the Referer.
/// The handoff token lives only in [url]'s fragment; nothing here logs,
/// stores, query-strings, or rewrites it.
void openExternalUrl(String url) {
  html.window.open(url, '_blank', 'noopener,noreferrer');
}
