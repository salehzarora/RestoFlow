import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';

/// KIOSK-001-103 §12/§15 — the RECEIPT branding authority for the kiosk.
///
/// The Dashboard-configured receipt logo (`receipt_logo_path/enabled/version`
/// on the restaurant row) + the authoritative restaurant name arrive through
/// the SAME token-proven device transport as everything else
/// (`get_device_printer_assignments`, widened to the kiosk principal by
/// migration 20260824090000). The device-local APPEARANCE logo is shell
/// branding only and is NEVER a receipt authority.
///
/// Fail-soft everywhere: no session / RPC failure / disabled logo / broken
/// bytes all degrade to the real restaurant NAME — never to the EMBER
/// fixture, and never to a blocked receipt.

/// Seam: null in demo/tests; the real root provides the shared repository.
final kioskPrinterAssignmentsReaderProvider =
    Provider<DevicePrinterAssignmentsReader?>((ref) => null);

/// One load per app run (the kiosk needs a stable identity, not a live feed).
final kioskPrinterAssignmentsProvider =
    FutureProvider<
      Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>?
    >((ref) async {
      final reader = ref.watch(kioskPrinterAssignmentsReaderProvider);
      if (reader == null) return null;
      return reader.load();
    });

/// Seam: the raw-bytes logo reader bound to the SAME anonymous device client
/// (no second Supabase client, no signed URL, nothing persisted).
final kioskReceiptLogoReaderProvider = Provider<DeviceReceiptLogoReader?>(
  (ref) => null,
);

/// The resolved receipt identity: the authoritative restaurant name plus the
/// Dashboard logo bytes when enabled AND readable.
class KioskReceiptBranding {
  const KioskReceiptBranding({
    required this.restaurantName,
    this.logoBytes,
    this.logoMime,
    this.logoVersion = 0,
  });

  final String? restaurantName;
  final Uint8List? logoBytes;
  final String? logoMime;
  final int logoVersion;

  bool get hasLogo => logoBytes != null && logoBytes!.isNotEmpty;
}

/// Resolves name + logo once per run; cached by Riverpod. A logo download
/// failure keeps the name (fail-soft); a missing session yields null and the
/// caller falls back to the device-local appearance display name.
final kioskReceiptBrandingProvider = FutureProvider<KioskReceiptBranding?>((
  ref,
) async {
  final result = await ref.watch(kioskPrinterAssignmentsProvider.future);
  if (result == null) return null;
  switch (result) {
    case Failure():
      return null;
    case Success(:final value):
      final name = value.restaurantName?.trim();
      if (!value.hasReceiptLogo) {
        return KioskReceiptBranding(restaurantName: name);
      }
      final reader = ref.watch(kioskReceiptLogoReaderProvider);
      if (reader == null) return KioskReceiptBranding(restaurantName: name);
      try {
        final logo = await reader.load(value.receiptLogoPath!);
        return KioskReceiptBranding(
          restaurantName: name,
          logoBytes: logo?.bytes,
          logoMime: logo?.mime,
          logoVersion: value.receiptLogoVersion,
        );
      } catch (_) {
        return KioskReceiptBranding(restaurantName: name);
      }
  }
});
