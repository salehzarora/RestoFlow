/// Conditional export of the platform-support handoff reader (ADMIN-126B) —
/// the same zero-dependency `dart:html` pattern as the print launchers.
///
/// Exposes `takeSupportHandoff()`: the one-time token from the launch URL's
/// FRAGMENT, removed from the address bar in the same breath. Non-web targets
/// have no address bar and return null, so support mode simply does not exist
/// there.
export 'support_handoff_stub.dart'
    if (dart.library.html) 'support_handoff_web.dart';
