import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/draft_recovery_controller.dart';
import 'package:restoflow_pos/src/state/order_setup_controller.dart';
import 'package:restoflow_pos/src/state/recent_orders_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/recovery_coordinator.dart';

/// PILOT-OPERATIONS-CORRECTIONS-001 — Finding 1: a rejected draft stays recoverable
/// after its confirmation is cleared, and Keep-current must NOT reset the current cart.
/// These drive the shared [PosRecoveryCoordinator] used by BOTH entry points.

const _fries = DemoMenuItem(
  id: 'fries-B',
  name: 'Fries B',
  priceMinor: 1500,
  categoryId: 'sides',
  categoryName: 'Sides',
);

SubmittedOrderView _view(String entryId) => SubmittedOrderView(
  orderNumber: 'DEMO-$entryId',
  orderType: OrderType.dineIn,
  currencyCode: 'ILS',
  subtotalMinor: 4200,
  lines: const <SubmittedLineView>[],
  orderId: 'local-$entryId',
  outboxEntryId: entryId,
  localOperationId: 'op-$entryId',
);

/// A minimal harness: a button that runs the coordinator's restore/discard so the test
/// can exercise the current-cart protection dialog exactly as the real callers do.
class _Harness extends ConsumerWidget {
  const _Harness(this.recovery);
  final PosDraftRecovery recovery;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton(
            key: const Key('do-restore'),
            onPressed: () =>
                PosRecoveryCoordinator(ref).restore(context, recovery),
            child: const Text('restore'),
          ),
          ElevatedButton(
            key: const Key('do-discard'),
            onPressed: () => PosRecoveryCoordinator(ref).discard(recovery),
            child: const Text('discard'),
          ),
        ],
      ),
    ),
  );
}

ProviderContainer _demo() {
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

/// Seeds a neverCreated shell for [entryId] + a matching, scope-valid recovery whose
/// draft is a single [_burger]. Returns the recovery.
PosDraftRecovery _seedRejected(
  ProviderContainer c,
  String entryId, {
  String? customerName,
}) {
  final recent = c.read(posRecentOrdersControllerProvider.notifier);
  final view = _view(entryId);
  recent.recordSubmitted(view);
  recent.markLocallyRejected(view.identity);
  final recovery = PosDraftRecovery(
    draft: const CartDraftSnapshot(
      currencyCode: 'ILS',
      lines: [
        CartDraftLine(
          menuItemId: 'burger-A',
          name: 'Burger A',
          basePriceMinor: 4200,
          quantity: 1,
        ),
      ],
    ),
    orderType: OrderType.dineIn,
    outboxEntryId: entryId,
    binding: c.read(posRecoveryBindingProvider),
    customerName: customerName,
  );
  c.read(posDraftRecoveryProvider.notifier).capture(recovery);
  return recovery;
}

bool _hasShell(ProviderContainer c, String entryId) => c
    .read(posRecentOrdersControllerProvider)
    .any((o) => o.isNeverCreated && o.order?.outboxEntryId == entryId);

Future<void> _pump(
  WidgetTester tester,
  ProviderContainer c,
  PosDraftRecovery r,
) => tester.pumpWidget(
  UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: _Harness(r),
    ),
  ),
);

void main() {
  testWidgets(
    'empty cart: restore restores directly, retires the shell + recovery',
    (tester) async {
      final c = _demo();
      final r = _seedRejected(c, 'eA', customerName: 'Alice');
      await _pump(tester, c, r);
      // Cart B is empty -> restore is direct (no dialog).
      await tester.tap(find.byKey(const Key('do-restore')));
      await tester.pumpAndSettle();
      final cart = c.read(cartControllerProvider);
      expect(cart.lines.single.menuItemId, 'burger-A'); // draft A restored
      expect(c.read(orderSetupControllerProvider).customerName, 'Alice');
      expect(c.read(posDraftRecoveryProvider).containsKey('eA'), isFalse);
      expect(_hasShell(c, 'eA'), isFalse);
    },
  );

  testWidgets('Finding 1C: Keep current KEEPS the current cart + setup', (
    tester,
  ) async {
    final c = _demo();
    final r = _seedRejected(c, 'eA');
    // Cart B is non-empty (fries) with its own customer name.
    c.read(cartControllerProvider.notifier).addItem(_fries);
    c.read(orderSetupControllerProvider.notifier).setCustomerName('Bob');
    await _pump(tester, c, r);
    await tester.tap(find.byKey(const Key('do-restore')));
    await tester.pumpAndSettle();
    // The decision dialog appears; choose Keep current.
    await tester.tap(find.byKey(const Key('recovery-keep-cart')));
    await tester.pumpAndSettle();
    // Cart B is UNCHANGED (still fries, still Bob) — the bug was resetting it.
    final cart = c.read(cartControllerProvider);
    expect(cart.lines.single.menuItemId, 'fries-B');
    expect(c.read(orderSetupControllerProvider).customerName, 'Bob');
    // A's shell + recovery are retired.
    expect(c.read(posDraftRecoveryProvider).containsKey('eA'), isFalse);
    expect(_hasShell(c, 'eA'), isFalse);
  });

  testWidgets('Replace replaces the cart with the rejected draft exactly once', (
    tester,
  ) async {
    final c = _demo();
    final r = _seedRejected(c, 'eA', customerName: 'Alice');
    c.read(cartControllerProvider.notifier).addItem(_fries); // cart B
    await _pump(tester, c, r);
    await tester.tap(find.byKey(const Key('do-restore')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('recovery-replace-cart')));
    await tester.pumpAndSettle();
    final cart = c.read(cartControllerProvider);
    // Cart replaced with A (burger), exactly one line; customer name restored.
    expect(cart.lines.length, 1);
    expect(cart.lines.single.menuItemId, 'burger-A');
    expect(c.read(orderSetupControllerProvider).customerName, 'Alice');
    expect(c.read(posDraftRecoveryProvider).containsKey('eA'), isFalse);
    expect(_hasShell(c, 'eA'), isFalse);
  });

  testWidgets('Cancel changes nothing (cart, shell, recovery all remain)', (
    tester,
  ) async {
    final c = _demo();
    final r = _seedRejected(c, 'eA');
    c.read(cartControllerProvider.notifier).addItem(_fries);
    await _pump(tester, c, r);
    await tester.tap(find.byKey(const Key('do-restore')));
    await tester.pumpAndSettle();
    // Dismiss the dialog via Cancel (the first TextButton).
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.read(cartControllerProvider).lines.single.menuItemId, 'fries-B');
    expect(c.read(posDraftRecoveryProvider).containsKey('eA'), isTrue);
    expect(_hasShell(c, 'eA'), isTrue);
  });

  testWidgets('Discard retires only the shell + its recovery; cart untouched', (
    tester,
  ) async {
    final c = _demo();
    final r = _seedRejected(c, 'eA');
    c.read(cartControllerProvider.notifier).addItem(_fries);
    await _pump(tester, c, r);
    await tester.tap(find.byKey(const Key('do-discard')));
    await tester.pumpAndSettle();
    expect(c.read(cartControllerProvider).lines.single.menuItemId, 'fries-B');
    expect(c.read(posDraftRecoveryProvider).containsKey('eA'), isFalse);
    expect(_hasShell(c, 'eA'), isFalse);
  });

  test('two rejected shells are isolated by exact outbox identity', () {
    final c = _demo();
    _seedRejected(c, 'eA');
    _seedRejected(c, 'eB');
    // Discard A only, by its exact outbox identity (what the coordinator does).
    c
        .read(posRecentOrdersControllerProvider.notifier)
        .retireLocalRejectedByOutboxEntry('eA');
    c.read(posDraftRecoveryProvider.notifier).clear('eA');
    expect(c.read(posDraftRecoveryProvider).containsKey('eA'), isFalse);
    expect(c.read(posDraftRecoveryProvider).containsKey('eB'), isTrue);
    expect(_hasShell(c, 'eA'), isFalse);
    expect(_hasShell(c, 'eB'), isTrue); // B untouched
  });

  test(
    'a PIN/scope mismatch makes the recovery unavailable (not restorable)',
    () {
      final c = _demo();
      _seedRejected(c, 'eA');
      final n = c.read(posDraftRecoveryProvider.notifier);
      // A different PIN session cannot recover it.
      const otherBinding = PosRecoveryBinding(
        scopeKey: 'demo-org.demo-restaurant.demo-branch.demo-device',
        pinSessionId: 'someone-else',
      );
      expect(n.recoverable('eA', otherBinding), isNull);
      // The rightful (current) context still can.
      expect(
        n.recoverable('eA', c.read(posRecoveryBindingProvider)),
        isNotNull,
      );
    },
  );
}
