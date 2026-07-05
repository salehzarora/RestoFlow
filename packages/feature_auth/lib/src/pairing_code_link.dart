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

/// LIVE-OPS-001 — the INVERSE of [pairingCodeFromUri]: build the hosted app link
/// a Dashboard shows (as a QR + copyable URL) so staff can open a tablet straight
/// onto the pairing screen with the code prefilled. POS/KDS are served at `/pos`
/// and `/kds` on the SAME origin as the Dashboard, so the link is
/// `{origin}/pos?pair=CODE` (or `/kds`). The operator still taps "Pair" — this is
/// prefill only, never an auto-redeem. The code is short-lived, single-use and
/// rate-limited server-side, so it is not a durable secret; it is never logged.

/// The hosted route segment for [deviceType]: `pos` or `kds`. Null for any other
/// (unknown) type — the caller then shows the manual code only, never a bad link.
String? pairingRouteForDeviceType(String deviceType) =>
    switch (deviceType.trim().toLowerCase()) {
      'pos' => 'pos',
      'kds' => 'kds',
      _ => null,
    };

/// Builds the pairing link for [deviceType] on the origin of [base] (scheme +
/// host + port ONLY — [base]'s path/query/fragment are dropped, so the Dashboard's
/// own URL never leaks in). Returns null for an unknown device type or a blank
/// code. The code is placed in the `pair` query parameter, so [Uri] percent-
/// encodes it safely. Pure + origin-derived: works on localhost, Vercel preview /
/// production, and any future custom domain — nothing is hardcoded.
Uri? pairingLinkForDeviceType({
  required Uri base,
  required String code,
  required String deviceType,
}) {
  final route = pairingRouteForDeviceType(deviceType);
  final trimmed = code.trim();
  if (route == null || trimmed.isEmpty) return null;
  return Uri(
    scheme: base.scheme,
    host: base.host,
    port: base.hasPort ? base.port : null,
    pathSegments: [route],
    queryParameters: {'pair': trimmed},
  );
}

/// The pairing link derived from the CURRENT web origin ([Uri.base]), or null
/// off-web / for an unknown type / blank code. Safe to call anywhere; never throws
/// and reads no secret.
Uri? pairingLinkUrlForDeviceType({
  required String code,
  required String deviceType,
}) => kIsWeb
    ? pairingLinkForDeviceType(
        base: Uri.base,
        code: code,
        deviceType: deviceType,
      )
    : null;
