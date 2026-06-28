import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_feature_kitchen/restoflow_feature_kitchen.dart';
import 'package:restoflow_kds/src/data/kitchen_orders_repository.dart';
import 'package:restoflow_kds/src/state/kitchen_orders_controller.dart';
import 'package:restoflow_sync/restoflow_sync.dart';

/// A minimal hand-written fake sync source (house style: no mocktail). Enough to
/// stand in for an injected real coordinator without any live Supabase, so the
/// test can prove the KDS source-injection pattern is preserved.
class _FakeKdsSyncSource implements KdsSyncSource {
  final StreamController<KdsSyncState> _controller =
      StreamController<KdsSyncState>.broadcast();

  @override
  KdsSyncState get state => KdsSyncState.initial;

  @override
  Stream<KdsSyncState> get states => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> refresh() async {}

  @override
  Future<void> dispose() async => _controller.close();
}

ProviderContainer _container({
  required bool isDemoMode,
  List<Override> overrides = const [],
}) {
  return ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: isDemoMode),
      ),
      ...overrides,
    ],
  );
}

void main() {
  group('KDS repo mode selection', () {
    test('demo mode (default) resolves DemoKitchenOrdersStore', () {
      final container = _container(isDemoMode: true);
      addTearDown(container.dispose);

      expect(
        container.read(kitchenOrdersRepositoryProvider),
        isA<DemoKitchenOrdersStore>(),
      );
    });

    test(
      'real mode resolves RealKitchenOrdersRepository that throws (no backend)',
      () async {
        final container = _container(isDemoMode: false);
        addTearDown(container.dispose);

        final repo = container.read(kitchenOrdersRepositoryProvider);
        expect(repo, isA<RealKitchenOrdersRepository>());
        await expectLater(
          repo.loadOrders(),
          throwsA(isA<RealRepoNotWiredError>()),
        );
      },
    );

    test(
      'kdsSyncSourceProvider throws UnimplementedError when not overridden',
      () {
        final container = _container(isDemoMode: false);
        addTearDown(container.dispose);

        expect(
          () => container.read(kdsSyncSourceProvider),
          throwsA(isA<UnimplementedError>()),
        );
      },
    );

    test(
      'kdsSyncSourceProvider returns the injected source when overridden',
      () {
        final fake = _FakeKdsSyncSource();
        addTearDown(fake.dispose);
        final container = _container(
          isDemoMode: false,
          overrides: [kdsSyncSourceProvider.overrideWithValue(fake)],
        );
        addTearDown(container.dispose);

        expect(container.read(kdsSyncSourceProvider), same(fake));
      },
    );
  });
}
