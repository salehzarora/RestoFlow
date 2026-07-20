import 'package:flutter/foundation.dart' show kIsWeb;

/// KITCHEN-MODE-001C2A — the injectable platform-capability seam for the
/// encrypted kitchen spool.
///
/// The pilot's supported printer-only target is NATIVE ANDROID POS. Web POS
/// has no Drift persistence and no Keystore, so it FAILS CLOSED: the secure
/// spool is reported unavailable (this typed capability is what the future
/// mode gating will consume) and no browser storage of any kind is ever used
/// as a fallback. Tests inject `isWeb` instead of relying on a real browser.
final class PosKitchenSpoolPlatform {
  const PosKitchenSpoolPlatform({bool? isWeb}) : _isWebOverride = isWeb;

  final bool? _isWebOverride;

  bool get isWeb => _isWebOverride ?? kIsWeb;

  /// Whether this platform can host the encrypted kitchen spool at all
  /// (Keystore-backed key + Drift database). `false` is a hard, fail-closed
  /// signal — printer-only readiness must report `secure_spool_available:
  /// false` here (001C3); there is NO degraded/plaintext mode.
  bool get supportsSecureSpool => !isWeb;
}
