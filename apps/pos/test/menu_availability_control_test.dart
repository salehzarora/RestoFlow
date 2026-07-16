import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/ids.dart';
import 'package:restoflow_pos/src/data/menu_availability_repository.dart';
import 'package:restoflow_pos/src/state/menu_availability_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/widgets/menu_availability_sheet.dart';
import 'package:restoflow_pos/src/widgets/menu_item_card.dart';

/// A transport that returns a canned envelope (or throws) for any RPC.
class _FakeTransport implements SyncRpcTransport {
  _FakeTransport(this._handler);
  final Object? Function(String fn, Map<String, dynamic> p) _handler;
  final List<(String, Map<String, dynamic>)> calls = [];
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    calls.add((function, params));
    return _handler(function, params);
  }
}

class _ThrowingTransport implements SyncRpcTransport {
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    throw const SyncTransportException(SyncTransportErrorKind.transient);
  }
}

Map<String, dynamic> _applied(String availability, String? reason) => {
  'ok': true,
  'results': [
    {
      'local_operation_id': 'ignored',
      'status': 'applied',
      'ok': true,
      'availability': availability,
      'reason': reason,
    },
  ],
};

/// A ClientIdGenerator returning a fixed id so the fake result matches.
class _FixedId implements ClientIdGenerator {
  @override
  String newId() => 'op-1';
}

Map<String, dynamic> _appliedFixed(String availability, String? reason) => {
  'ok': true,
  'results': [
    {
      'local_operation_id': 'op-1',
      'status': 'applied',
      'ok': true,
      'availability': availability,
      'reason': reason,
    },
  ],
};

const _session = SyncSession(pinSessionId: 'pin-1', deviceId: 'dev-1');

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  group('RealMenuAvailabilityRepository', () {
    test('applies a Sold out set and returns the confirmed state', () async {
      final t = _FakeTransport(
        (fn, p) => _appliedFixed('unavailable', 'sold_out'),
      );
      final repo = RealMenuAvailabilityRepository(t, _session, _FixedId());
      final state = await repo.setAvailability(
        menuItemId: 'item-1',
        availability: 'unavailable',
        reason: 'sold_out',
      );
      expect(state.availability, 'unavailable');
      expect(state.reason, 'sold_out');
      // it dispatched the menu.availability_set op via sync_push
      final op = (t.calls.single.$2['p_operations'] as List).single as Map;
      expect(op['operation_type'], 'menu.availability_set');
      expect((op['payload'] as Map)['menu_item_id'], 'item-1');
    });

    test('maps a permission_denied result to the typed exception', () async {
      final t = _FakeTransport(
        (fn, p) => {
          'ok': true,
          'results': [
            {
              'local_operation_id': 'op-1',
              'status': 'rejected',
              'ok': false,
              'error': 'permission_denied',
            },
          ],
        },
      );
      final repo = RealMenuAvailabilityRepository(t, _session, _FixedId());
      expect(
        () => repo.setAvailability(menuItemId: 'i', availability: 'available'),
        throwsA(
          isA<MenuAvailabilityException>().having(
            (e) => e.code,
            'code',
            'permission_denied',
          ),
        ),
      );
    });

    test('OFFLINE: with no session it throws offline, never fake success', () {
      final repo = RealMenuAvailabilityRepository(
        _FakeTransport((fn, p) => _applied('available', null)),
        null,
        _FixedId(),
      );
      expect(
        () => repo.setAvailability(menuItemId: 'i', availability: 'available'),
        throwsA(
          isA<MenuAvailabilityException>().having(
            (e) => e.code,
            'code',
            'offline',
          ),
        ),
      );
    });

    test('a transport failure is the retryable offline case', () {
      final repo = RealMenuAvailabilityRepository(
        _ThrowingTransport(),
        _session,
        _FixedId(),
      );
      expect(
        () => repo.setAvailability(menuItemId: 'i', availability: 'available'),
        throwsA(
          isA<MenuAvailabilityException>().having(
            (e) => e.code,
            'code',
            'offline',
          ),
        ),
      );
    });
  });

  test(
    'demo overlay: a demo Sold-out is honestly reflected by posMenuProvider',
    () async {
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: true),
          ),
        ],
      );
      addTearDown(container.dispose);
      final before = await container.read(posMenuProvider.future);
      final target = before.items.firstWhere((i) => !i.isUnavailable);
      // Mutate via the demo repository from the provider seam (honest demo success).
      await container
          .read(menuAvailabilityRepositoryProvider)
          .setAvailability(
            menuItemId: target.id,
            availability: 'unavailable',
            reason: 'paused',
          );
      final after = await container.read(posMenuProvider.future);
      final now = after.items.firstWhere((i) => i.id == target.id);
      expect(now.isUnavailable, isTrue);
      expect(now.availabilityReason, 'paused');
    },
  );

  testWidgets('an unavailable tile is not addable but the management action '
      'is still reachable', (tester) async {
    var added = 0;
    var managed = 0;
    const item = DemoMenuItem(
      id: 'sold-out-1',
      name: 'Onion rings',
      priceMinor: 1800,
      categoryId: 'sides',
      categoryName: 'Sides',
      availability: 'unavailable',
      availabilityReason: 'sold_out',
    );
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 240,
            height: 320,
            child: MenuItemCard(
              item: item,
              onAdd: () => added++,
              onManageAvailability: () => managed++,
            ),
          ),
        ),
      ),
    );
    // Normal tap must NOT add an unavailable item.
    await tester.tap(find.byKey(const Key('menu-item-sold-out-1')));
    await tester.pump();
    expect(added, 0);
    // The deliberate management gesture still fires.
    await tester.longPress(find.byKey(const Key('menu-item-sold-out-1')));
    await tester.pump();
    expect(managed, 1);
  });

  testWidgets('the availability sheet submits a choice and closes on success', (
    tester,
  ) async {
    final l10n = await _en();
    const item = DemoMenuItem(
      id: 'burger-1',
      name: 'Classic burger',
      priceMinor: 4200,
      categoryId: 'burgers',
      categoryName: 'Burgers',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: true),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: restoflowLocalizationsDelegates,
          supportedLocales: kSupportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: const Key('open-avail'),
                  onPressed: () =>
                      MenuAvailabilitySheet.show(context, item: item),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open-avail')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.posMenuChangeAvailability), findsOneWidget);
    await tester.tap(find.byKey(const Key('availability-option-sold-out')));
    await tester.pumpAndSettle();
    // The sheet closed (success) — the title is gone and no error banner.
    expect(find.text(l10n.posMenuChangeAvailability), findsNothing);
    expect(find.byKey(const Key('availability-error')), findsNothing);
  });
}
