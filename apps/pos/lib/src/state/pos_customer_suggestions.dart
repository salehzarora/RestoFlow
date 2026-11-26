import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/customer_phone.dart';
import '../data/order_submission.dart' show kCustomerNameMaxLength;
import 'pos_device_context.dart';
import 'pos_offline_state.dart';
import 'pos_session.dart';
import 'pos_sync_scope_provider.dart';

class PosCustomerSuggestion {
  const PosCustomerSuggestion({required this.name, required this.phone});

  final String name;
  final String phone;
}

final _searchCharacter = RegExp(r'[\p{L}\p{N}]', unicode: true);

/// The phone's display format stays on the order. Only its search key is folded.
String? posCustomerSuggestionPrefix(String input, {required bool byPhone}) {
  final trimmed = input.trim();
  if (!byPhone) {
    final name = trimmed.replaceAll(RegExp(r'\s+'), ' ');
    return name.length <= kCustomerNameMaxLength &&
            _searchCharacter.allMatches(name).take(2).length == 2
        ? name
        : null;
  }
  if (trimmed.length > kCustomerPhoneMaxLength ||
      !RegExp(r'^[0-9٠-٩۰-۹+() -]+$').hasMatch(trimmed)) {
    return null;
  }
  final digits = trimmed.replaceAll(RegExp(r'[+() -]'), '').replaceAllMapped(
    RegExp(r'[٠-٩۰-۹]'),
    (match) {
      final digit = match[0]!.codeUnitAt(0);
      return (digit - (digit >= 0x6f0 ? 0x6f0 : 0x660)).toString();
    },
  );
  return digits.length >= 4 ? digits : null;
}

/// Suggestions are ephemeral. A change of pairing, PIN, branch or offline
/// state must invalidate even a response already in flight.
final posCustomerSuggestionsScopeProvider = Provider<String?>((ref) {
  final scope = ref.watch(posSyncScopeProvider);
  final pin = ref.watch(posSyncSessionProvider);
  final device = ref.watch(posDeviceContextProvider);
  final online = ref.watch(
    posOfflineModeProvider.select(
      (state) => state.phase == PosOfflinePhase.online,
    ),
  );
  if (!online ||
      scope == null ||
      pin == null ||
      device == null ||
      !device.isPaired ||
      device.deviceType != 'pos' ||
      device.deviceId != pin.deviceId ||
      device.deviceSessionId == null) {
    return null;
  }
  return '${scope.key}|${device.deviceSessionId}|${pin.pinSessionId}';
});

typedef PosCustomerSuggestionsLookup =
    Future<List<PosCustomerSuggestion>> Function(
      String query, {
      required bool byPhone,
    });

final posCustomerSuggestionsLookupProvider =
    Provider<PosCustomerSuggestionsLookup>((ref) {
      final scope = ref.watch(posCustomerSuggestionsScopeProvider);
      final pin = ref.watch(posSyncSessionProvider);
      final transport = ref.watch(posAuthTransportProvider);
      return (query, {required byPhone}) async {
        final prefix = posCustomerSuggestionPrefix(query, byPhone: byPhone);
        if (prefix == null ||
            scope == null ||
            pin == null ||
            transport == null) {
          return const [];
        }
        final response = await transport.invoke('pos_customer_suggestions', {
          'p_pin_session_id': pin.pinSessionId,
          'p_query': prefix,
          'p_by_phone': byPhone,
        });
        if (response is! List) return const [];
        final suggestions = <PosCustomerSuggestion>[];
        for (final entry in response.take(5)) {
          if (entry case {
            'name': final String name,
            'phone': final String phone,
          }) {
            if (name.trim().isNotEmpty &&
                name.length <= kCustomerNameMaxLength &&
                normalizeCustomerPhone(phone) != null) {
              suggestions.add(PosCustomerSuggestion(name: name, phone: phone));
            }
          }
        }
        return suggestions;
      };
    });
