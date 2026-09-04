/// AUTH-256 — conditional export of the address-bar rewriter used to scrub an
/// auth callback out of the URL, matching the pattern the print launchers and
/// the support handoff already use.
export 'auth_url_stub.dart' if (dart.library.html) 'auth_url_web.dart';
