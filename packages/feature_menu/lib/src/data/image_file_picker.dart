/// Conditional export of the zero-dependency platform image-file picker
/// (menu/media sprint — same pattern as the POS `browser_print` launcher).
///
/// Exposes:
///  * `pickMenuImageFile()` — opens the platform file picker restricted to the
///    RF-110 image MIME types and resolves with the picked bytes (or null on
///    cancel / unsupported platform);
///  * `menuImagePickerSupported` — whether THIS build target has a picker
///    (web: true; everything else: false — the UI shows an honest
///    "not available on this platform" note instead of a dead button).
export 'image_file_picker_stub.dart'
    if (dart.library.html) 'image_file_picker_web.dart';
