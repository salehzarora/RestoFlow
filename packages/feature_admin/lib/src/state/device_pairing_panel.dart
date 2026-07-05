import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// LIVE-OPS-001 — a HOST-PROVIDED "pairing panel" seam.
///
/// When the Dashboard issues a device enrollment code it wants to show a rich
/// pairing panel (a QR code + a copyable hosted link + the manual code), so staff
/// can point a tablet straight at the pairing screen. QR rendering is a Dashboard
/// concern (it owns the `qr_flutter` dependency); `feature_admin` stays free of it.
/// So the Dashboard injects a [PairingPanelPresenter] via [devicePairingPanelProvider]
/// and the Devices screen calls it on a successful issue. When no presenter is
/// injected (tests, or a host that doesn't provide one) the screen falls back to
/// the plain one-time-code dialog — no behaviour is lost.
class PairingPanelRequest {
  const PairingPanelRequest({
    required this.deviceLabel,
    required this.deviceType,
    required this.code,
  });

  /// The device's display label (e.g. "Counter POS").
  final String deviceLabel;

  /// `pos` | `kds` | (any other type -> the panel shows the manual code only,
  /// never a wrong app link).
  final String deviceType;

  /// The one-time enrollment code. Short-lived, single-use, rate-limited
  /// server-side — never logged, never persisted.
  final String code;
}

/// Presents the pairing panel for [request]; the returned future completes when
/// the panel is dismissed.
typedef PairingPanelPresenter =
    Future<void> Function(BuildContext context, PairingPanelRequest request);

/// The optional host pairing-panel presenter. Null by default (feature_admin
/// ships NO QR dependency); the Dashboard overrides it with a QR-capable panel.
final devicePairingPanelProvider = Provider<PairingPanelPresenter?>(
  (ref) => null,
);
