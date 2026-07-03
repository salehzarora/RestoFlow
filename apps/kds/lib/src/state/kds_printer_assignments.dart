import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';

/// The token-proven printer-assignments reader for THIS paired KDS display
/// (device settings sprint). Null by default (demo mode / unconfigured real
/// mode — the settings sheet then shows no printer data instead of faking
/// any). Overridden in `main.dart` with the real repository riding the same
/// anonymous device transport. The server serves KITCHEN printers only to a
/// KDS device — and never money (T-003/T-014).
final kdsPrinterAssignmentsReaderProvider =
    Provider<DevicePrinterAssignmentsReader?>((ref) => null);

/// The current printer-assignment snapshot for this display, or null when no
/// reader is wired. Refresh = `ref.invalidate(kdsPrinterAssignmentsProvider)`
/// (the ⋮ menu's "Refresh connection"). Failures surface as typed values —
/// the sheet renders a safe error, never a fake "Ready".
final kdsPrinterAssignmentsProvider =
    FutureProvider<
      Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>?
    >((ref) async {
      final reader = ref.watch(kdsPrinterAssignmentsReaderProvider);
      if (reader == null) return null;
      return reader.load();
    });
