import 'package:flutter/foundation.dart' show kIsWeb;

/// LIVE-DEVICE-001 — pairing-code URL prefill (UI-only; no backend change).
///
/// A hosted tablet can be pointed at `…/pos?pair=CODE` (or `…/kds?pair=CODE`) —
/// e.g. from a Dashboard-generated link or a QR that encodes that link — so staff
/// do not have to type the enrollment code by hand. The device pairing screen
/// PREFILLS the code from the URL; the operator still taps "Pair" (no silent
/// auto-redeem of a single-use code). The code is NOT a long-lived secret (it is
/// short-lived, single-use, and rate-limited server-side), and it is never logged.
///
/// [pairingCodeFromUri] is the pure, testable core; [pairingCodeFromUrl] is the
/// web wrapper reading [Uri.base]. On a non-web build there is no URL prefill.

/// The `pair` query parameter of [uri], trimmed; null when absent or blank.
String? pairingCodeFromUri(Uri uri) {
  final code = uri.queryParameters['pair']?.trim();
  return (code == null || code.isEmpty) ? null : code;
}

/// The pairing code from the current web URL (`?pair=…`), or null off-web / when
/// absent. Safe to call anywhere; reads no secret and never throws.
String? pairingCodeFromUrl() => kIsWeb ? pairingCodeFromUri(Uri.base) : null;
