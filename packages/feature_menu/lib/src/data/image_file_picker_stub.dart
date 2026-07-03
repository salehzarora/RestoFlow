import 'picked_menu_image.dart';

/// Whether this build target has a native file picker. Non-web targets have
/// none (no dependency-free path) — the image panel shows an honest
/// "not available on this platform" note instead of a dead button.
const bool menuImagePickerSupported = false;

/// Non-web targets: no picker — resolves null (the UI never fakes a pick).
Future<PickedMenuImage?> pickMenuImageFile() async => null;
