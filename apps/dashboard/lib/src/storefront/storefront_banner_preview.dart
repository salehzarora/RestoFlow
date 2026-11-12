/// Render-only browser preview; persistence and draft ownership stay in the editor.
library;

export 'storefront_banner_preview_geometry.dart';
export 'storefront_banner_preview_stub.dart'
    if (dart.library.js_interop) 'storefront_banner_preview_web.dart';
