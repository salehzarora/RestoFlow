import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

/// The token-proven per-branch "Close shift & count cash" visibility policy
/// reader for THIS paired POS station (RF-113). Null by default (demo mode /
/// unconfigured real mode). Overridden in `main.dart` with the real repository
/// riding the same anonymous device transport as the other device reads.
final posShiftClosePolicyReaderProvider =
    Provider<DeviceShiftClosePolicyReader?>((ref) => null);

/// Whether the POS should show the shift-close / cash-reconciliation workflow
/// for this station's branch. DEFAULT TRUE (RF-113 is visible by default, incl.
/// demo mode and while the real read is in flight or after a read glitch) — the
/// owner can DISABLE it from the Dashboard. Only a confirmed `false` from the
/// backend hides the ⋮ "Close shift" entry; payments/orders are unaffected (the
/// server still requires an open shift internally). Refresh via
/// `ref.invalidate(posShiftCloseEnabledProvider)`.
final posShiftCloseEnabledProvider = FutureProvider<bool>((ref) async {
  final reader = ref.watch(posShiftClosePolicyReaderProvider);
  if (reader == null) return true;
  final enabled = await reader.load();
  return enabled ?? true;
});
