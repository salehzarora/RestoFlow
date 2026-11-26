import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_pos/src/state/pos_customer_suggestions.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';

class _Transport implements SyncRpcTransport {
  final calls = <Map<String, dynamic>>[];
  Object? response;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    expect(function, 'pos_customer_suggestions');
    calls.add(params);
    return response;
  }
}

void main() {
  test(
    'prefixes support cashier languages and local or international numbers',
    () {
      for (final input in ['', 'م', 'א', 'A ', '%_', 'م-']) {
        expect(posCustomerSuggestionPrefix(input, byPhone: false), isNull);
      }
      for (final input in ['مح', 'של', 'Mo']) {
        expect(posCustomerSuggestionPrefix(input, byPhone: false), input);
      }
      expect(
        posCustomerSuggestionPrefix('  محمد  مس ', byPhone: false),
        'محمد مس',
      );
      expect(posCustomerSuggestionPrefix('٠٥۰ ١', byPhone: true), '0501');
      expect(posCustomerSuggestionPrefix('(+972) 50-', byPhone: true), '97250');
      for (final input in ['٠٥٠-', '05x03', '%1234']) {
        expect(posCustomerSuggestionPrefix(input, byPhone: true), isNull);
      }
    },
  );

  test(
    'bound read sends PIN and prefix only and keeps valid display fields',
    () async {
      final transport = _Transport()
        ..response = [
          {'name': 'محمد مسعود', 'phone': '050-0000001'},
          {'name': 'Missing phone'},
          {'name': '', 'phone': '050000001'},
          {'name': 'Invalid phone', 'phone': '?'},
        ];
      final container = ProviderContainer(
        overrides: [
          posSyncSessionProvider.overrideWithValue(
            const SyncSession(pinSessionId: 'pin', deviceId: 'device'),
          ),
          posCustomerSuggestionsScopeProvider.overrideWithValue(
            'authorized-scope',
          ),
          posAuthTransportProvider.overrideWithValue(transport),
        ],
      );
      addTearDown(container.dispose);
      final lookup = container.read(posCustomerSuggestionsLookupProvider);
      expect(await lookup('050', byPhone: true), isEmpty);
      final rows = await lookup('٠٥٠-٠', byPhone: true);
      expect(transport.calls, [
        {'p_pin_session_id': 'pin', 'p_query': '0500', 'p_by_phone': true},
      ]);
      expect(rows.single.name, 'محمد مسعود');
      expect(rows.single.phone, '050-0000001');
    },
  );

  test('unpaired or unavailable scope sends no search', () async {
    final transport = _Transport();
    final container = ProviderContainer(
      overrides: [
        posSyncSessionProvider.overrideWithValue(
          const SyncSession(pinSessionId: 'pin', deviceId: 'device'),
        ),
        posCustomerSuggestionsScopeProvider.overrideWithValue(null),
        posAuthTransportProvider.overrideWithValue(transport),
      ],
    );
    addTearDown(container.dispose);
    expect(
      await container.read(posCustomerSuggestionsLookupProvider)(
        'محمد',
        byPhone: false,
      ),
      isEmpty,
    );
    expect(transport.calls, isEmpty);
  });
}
