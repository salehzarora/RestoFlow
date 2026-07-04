import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';

/// The token-proven per-branch TAX setting reader for THIS paired POS station
/// (RF-117). Null by default (demo mode / unconfigured real mode). Overridden in
/// `main.dart` with the real repository riding the same anonymous device
/// transport as the other device reads (printer assignments, shift-close policy).
final posBranchTaxReaderProvider = Provider<DeviceBranchTaxReader?>(
  (ref) => null,
);

/// The branch tax setting the POS uses to display tax and to include
/// `tax_total_minor` in a submitted order (RF-117).
///
/// DEFAULT [BranchTax.disabled] — tax is OFF unless the owner enabled it (no
/// jurisdiction is frozen; Q-001/Q-002). This DIFFERS from the default-true
/// shift-close policy on purpose: a read glitch or an unconfigured device must
/// never invent a tax the owner did not set. Only a confirmed `enabled` setting
/// from the token-proven device read turns the tax line on. Demo mode has no
/// reader, so it stays OFF (existing demo/e2e flows submit tax = 0 unchanged).
/// Refresh via `ref.invalidate(posBranchTaxProvider)`.
final posBranchTaxProvider = FutureProvider<BranchTax>((ref) async {
  final reader = ref.watch(posBranchTaxReaderProvider);
  if (reader == null) return BranchTax.disabled;
  final tax = await reader.load();
  return tax ?? BranchTax.disabled;
});
