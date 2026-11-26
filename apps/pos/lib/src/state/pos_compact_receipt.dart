import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pos_device_context.dart';

/// A till can use the faster roll printer alongside a printer that requires
/// paced writes. The choice belongs to the saved physical destination.
final posCompactReceiptProvider =
    AsyncNotifierProvider.family<PosCompactReceiptController, bool, String>(
      PosCompactReceiptController.new,
    );

class PosCompactReceiptController extends FamilyAsyncNotifier<bool, String> {
  String _key(String segment) =>
      'restoflow.printer.compact_receipt.pos.'
      '${Uri.encodeComponent(segment)}/${Uri.encodeComponent(arg)}';

  @override
  Future<bool> build(String arg) async {
    final segment = await ref.watch(posPrinterScopeSegmentProvider.future);
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_key(segment)) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setEnabled(bool enabled) async {
    final previous = state.asData;
    final segment = ref.read(posPrinterScopeSegmentProvider).asData?.value;
    if (state.isLoading || previous == null || segment == null) return false;
    state = const AsyncLoading<bool>().copyWithPrevious(previous);
    var saved = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      saved = await prefs.setBool(_key(segment), enabled);
    } catch (_) {
      // An unavailable preference store keeps the previous print mode.
    }
    if (ref.read(posPrinterScopeSegmentProvider).asData?.value == segment) {
      state = saved ? AsyncData(enabled) : previous;
    }
    return saved;
  }
}
