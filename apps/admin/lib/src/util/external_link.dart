/// Conditional export of the zero-dependency external-link opener (the same
/// dart:html pattern as the POS/KDS browser print launchers): the web variant
/// opens the URL in a new tab; the stub is a no-op on non-web builds.
export 'external_link_stub.dart'
    if (dart.library.html) 'external_link_web.dart';
