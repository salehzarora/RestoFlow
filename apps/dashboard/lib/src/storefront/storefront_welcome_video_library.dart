import 'storefront_welcome_video_models.dart';

/// Implemented by the existing scoped content repository. Null means an
/// unavailable/malformed/denied read, never an accepted empty video library.
abstract interface class StorefrontWelcomeVideoLibrary {
  Future<List<StorefrontWelcomeVideoMedia>?> listWelcomeVideos();
}
