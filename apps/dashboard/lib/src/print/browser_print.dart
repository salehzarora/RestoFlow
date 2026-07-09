/// Conditional export of the platform isolated-browser-print launcher
/// (ORDERS-HISTORY-001; dashboard-local copy of the POS/KDS mechanism).
///
/// Exposes `printHtmlDocument(html, title)` — the web variant opens the document
/// in an isolated window and prints only it; the stub is a no-op on non-web.
export 'browser_print_stub.dart'
    if (dart.library.html) 'browser_print_web.dart';
