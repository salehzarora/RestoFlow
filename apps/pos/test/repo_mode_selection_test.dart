import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/data/demo_tables.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/data/payment_repository.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/payment_controller.dart';

/// RF (M7): the POS payment/outbox/tables seams pick Demo* (default) vs Real*
/// purely from [runtimeConfigProvider]. No SupabaseClient, no network - the test
/// only proves the SELECTION and that Real* skeletons refuse to contact a
/// backend (they throw [RealRepoNotWiredError]).
void main() {
  ProviderContainer containerFor({required bool isDemoMode}) {
    final container = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: isDemoMode),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  group('POS repo mode selection', () {
    test('demo mode (the default) resolves the Demo* repositories', () {
      final container = containerFor(isDemoMode: true);

      expect(
        container.read(paymentRepositoryProvider),
        isA<DemoPaymentStore>(),
      );
      expect(container.read(outboxRepositoryProvider), isA<DemoOutboxStore>());
      expect(container.read(tablesRepositoryProvider), isA<DemoTablesStore>());
    });

    test(
      'real mode resolves Real* skeletons that never contact a backend',
      () async {
        final container = containerFor(isDemoMode: false);

        final payment = container.read(paymentRepositoryProvider);
        final outbox = container.read(outboxRepositoryProvider);
        final tables = container.read(tablesRepositoryProvider);

        expect(payment, isA<RealPaymentRepository>());
        expect(outbox, isA<RealOutboxRepository>());
        expect(tables, isA<RealTablesRepository>());

        // Calling a method proves the skeleton fails loudly (no fake success, no
        // silent demo fallback) and so contacts no backend - integer minor units
        // are used throughout; no float is introduced.
        await expectLater(
          payment.recordCashPayment(
            orderNumber: 'DEMO-0001',
            amountMinor: 1000,
            tenderedMinor: 1000,
            currencyCode: 'ILS',
          ),
          throwsA(isA<RealRepoNotWiredError>()),
        );
        await expectLater(
          outbox.recentEntries(),
          throwsA(isA<RealRepoNotWiredError>()),
        );
        await expectLater(
          tables.loadTables(),
          throwsA(isA<RealRepoNotWiredError>()),
        );
      },
    );
  });
}
