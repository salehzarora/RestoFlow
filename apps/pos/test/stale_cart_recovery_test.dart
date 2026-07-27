import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/order_submission.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/draft_recovery_controller.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/order_confirmation.dart';

class _FakeOutbox extends OutboxController {
  _FakeOutbox(this.entries);
  final List<OutboxEntry> entries;
  @override
  List<OutboxEntry> build() => entries;
}

OutboxEntry _entry(OutboxSyncState state, {String? code, String? detail}) =>
    OutboxEntry(
      id: 'e1',
      deviceId: 'dev-1',
      localOperationId: 'op-1',
      operationType: 'order.submit',
      targetEntity: 'order',
      targetId: 'order-1',
      payloadJson: '{}',
      summary: const OrderSummary(
        orderNumber: 'DEMO-1',
        orderType: OrderType.takeaway,
        tableLabel: null,
        itemCount: 1,
        subtotalMinor: 4200,
        currencyCode: 'ILS',
        customerName: null,
      ),
      syncState: state,
      clientCreatedAt: DateTime.utc(2026, 7, 16),
      lastErrorCode: code,
      lastErrorDetail: detail,
    );

const _order = SubmittedOrderView(
  orderNumber: 'DEMO-1',
  orderType: OrderType.takeaway,
  currencyCode: 'ILS',
  subtotalMinor: 4200,
  lines: [
    SubmittedLineView(
      name: 'Classic burger',
      quantity: 1,
      lineTotalMinor: 4200,
      currencyCode: 'ILS',
    ),
  ],
  outboxEntryId: 'e1',
  orderId: 'order-1',
  localOperationId: 'op-1',
);

const _burger = DemoMenuItem(
  id: 'burger-1',
  name: 'Classic burger',
  priceMinor: 4200,
  categoryId: 'burgers',
  categoryName: 'Burgers',
);
const _fries = DemoMenuItem(
  id: 'fries-1',
  name: 'Fries',
  priceMinor: 1500,
  categoryId: 'sides',
  categoryName: 'Sides',
);

ProviderContainer _demoContainer() {
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
    ],
  );
  addTearDownContainer(c);
  return c;
}

final _tearDowns = <ProviderContainer>[];
void addTearDownContainer(ProviderContainer c) => _tearDowns.add(c);

void main() {
  tearDown(() {
    for (final c in _tearDowns) {
      c.dispose();
    }
    _tearDowns.clear();
  });

  group('CartController draft capture/restore', () {
    test(
      'captures products, quantities and notes, and restores them exactly',
      () {
        final c = _demoContainer();
        final cart = c.read(cartControllerProvider.notifier);
        cart.addItem(_burger);
        cart.addItem(_burger); // quantity 2
        cart.addItemWithModifiers(_fries, const [], note: 'extra crispy');

        final draft = cart.captureDraft();
        expect(draft.lines.length, 2);
        final burgerLine = draft.lines.firstWhere(
          (l) => l.menuItemId == 'burger-1',
        );
        expect(burgerLine.quantity, 2);
        final friesLine = draft.lines.firstWhere(
          (l) => l.menuItemId == 'fries-1',
        );
        expect(friesLine.note, 'extra crispy');

        // Clearing empties the cart; restore rebuilds it exactly.
        cart.clear();
        expect(c.read(cartControllerProvider).lines, isEmpty);
        cart.restoreDraft(draft);

        final restored = c.read(cartControllerProvider);
        expect(restored.lines.length, 2);
        final rb = restored.lines.firstWhere((l) => l.menuItemId == 'burger-1');
        expect(rb.quantity, 2);
        final rf = restored.lines.firstWhere((l) => l.menuItemId == 'fries-1');
        expect(rf.note, 'extra crispy');
      },
    );

    test('restore is idempotent — restoring twice never duplicates lines', () {
      final c = _demoContainer();
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItem(_burger);
      final draft = cart.captureDraft();
      cart.clear();
      cart.restoreDraft(draft);
      cart.restoreDraft(draft); // second delivery of the same recovery
      expect(c.read(cartControllerProvider).lines.length, 1);
    });

    // MENU-ORDER-001 (Codex #8/#9): the Dashboard menu ranks must survive a
    // submit -> reject(item_unavailable) -> Back-to-cart round-trip, so the
    // corrected resubmit still prints in menu order (a submit clears the live
    // _lineDisplayOrders, so the draft has to carry them).
    const cola = DemoMenuItem(
      id: 'cola-1',
      name: 'Cola',
      priceMinor: 1000,
      categoryId: 'drinks',
      categoryName: 'Drinks',
      categoryDisplayOrder: 3,
      itemDisplayOrder: 2,
    );
    const mealBurger = DemoMenuItem(
      id: 'burger-9',
      name: 'Burger',
      priceMinor: 4200,
      categoryId: 'meals',
      categoryName: 'Meals',
      categoryDisplayOrder: 1,
      itemDisplayOrder: 1,
    );

    test('capture carries each line\'s Dashboard menu ranks', () {
      final c = _demoContainer();
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItem(cola); // inserted first, but menu-ranks last
      cart.addItem(mealBurger); // inserted second, but menu-ranks first

      final draft = cart.captureDraft();
      final colaLine = draft.lines.firstWhere((l) => l.menuItemId == 'cola-1');
      final burgerLine = draft.lines.firstWhere(
        (l) => l.menuItemId == 'burger-9',
      );
      expect(
        (colaLine.categoryDisplayOrder, colaLine.itemDisplayOrder),
        (3, 2),
      );
      expect(
        (burgerLine.categoryDisplayOrder, burgerLine.itemDisplayOrder),
        (1, 1),
      );
    });

    test('restore REPOPULATES the ranks (not reset to 0) for the resubmit', () {
      final c = _demoContainer();
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItem(cola);
      cart.addItem(mealBurger);
      final draft = cart.captureDraft();

      // A submit clears the live _lineDisplayOrders; restore must rebuild them.
      cart.clear();
      cart.restoreDraft(draft);

      final draft2 = cart.captureDraft();
      final colaLine = draft2.lines.firstWhere((l) => l.menuItemId == 'cola-1');
      final burgerLine = draft2.lines.firstWhere(
        (l) => l.menuItemId == 'burger-9',
      );
      expect(
        (colaLine.categoryDisplayOrder, colaLine.itemDisplayOrder),
        (3, 2),
        reason: 'restore rebuilt the ranks (would be (0,0) if lost)',
      );
      expect(
        (burgerLine.categoryDisplayOrder, burgerLine.itemDisplayOrder),
        (1, 1),
      );
    });

    test(
      'viewFromDraft carries the ranks onto the recovered submitted view',
      () {
        final c = _demoContainer();
        final cart = c.read(cartControllerProvider.notifier);
        cart.addItem(cola);
        cart.addItem(mealBurger);
        final draft = cart.captureDraft();

        final view = cart.viewFromDraft(draft: draft);
        final colaLine = view.lines.firstWhere((l) => l.name == 'Cola');
        final burgerLine = view.lines.firstWhere((l) => l.name == 'Burger');
        expect(
          (colaLine.categoryDisplayOrder, colaLine.itemDisplayOrder),
          (3, 2),
        );
        expect(
          (burgerLine.categoryDisplayOrder, burgerLine.itemDisplayOrder),
          (1, 1),
        );
      },
    );
  });

  group('PosDraftRecoveryController', () {
    PosDraftRecovery mk(
      String entryId, {
      PosRecoveryBinding binding = const PosRecoveryBinding(),
    }) => PosDraftRecovery(
      draft: const CartDraftSnapshot(currencyCode: 'ILS', lines: []),
      orderType: OrderType.takeaway,
      outboxEntryId: entryId,
      binding: binding,
    );

    test('capture / clear (keyed by outbox entry id)', () {
      final c = ProviderContainer();
      addTearDownContainer(c);
      final n = c.read(posDraftRecoveryProvider.notifier);
      expect(c.read(posDraftRecoveryProvider), isEmpty);
      n.capture(mk('e1'));
      expect(c.read(posDraftRecoveryProvider).containsKey('e1'), isTrue);
      n.clear('e1');
      expect(c.read(posDraftRecoveryProvider), isEmpty);
    });

    test('clearIfFor only clears the matching entry', () {
      final c = ProviderContainer();
      addTearDownContainer(c);
      final n = c.read(posDraftRecoveryProvider.notifier);
      n.capture(mk('e2'));
      n.clearIfFor('other'); // does not match -> keep
      expect(c.read(posDraftRecoveryProvider).containsKey('e2'), isTrue);
      n.clearIfFor('e2'); // matches -> cleared
      expect(c.read(posDraftRecoveryProvider), isEmpty);
    });

    test(
      'MULTI-SLOT: two pending submits keep independent records (not latest-only)',
      () {
        final c = ProviderContainer();
        addTearDownContainer(c);
        final n = c.read(posDraftRecoveryProvider.notifier);
        n.capture(mk('e1'));
        n.capture(mk('e2'));
        // Both survive — B never erased A.
        final map = c.read(posDraftRecoveryProvider);
        expect(map.containsKey('e1'), isTrue);
        expect(map.containsKey('e2'), isTrue);
        // Clearing one leaves the other.
        n.clear('e1');
        final after = c.read(posDraftRecoveryProvider);
        expect(after.containsKey('e1'), isFalse);
        expect(after.containsKey('e2'), isTrue);
      },
    );
  });

  group('OrderConfirmation recovery UI', () {
    Future<ProviderContainer> pump(
      WidgetTester tester,
      OutboxSyncState state, {
      String? code,
      bool withRecovery = true,
    }) async {
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: true),
          ),
          outboxControllerProvider.overrideWith(
            () =>
                _FakeOutbox([_entry(state, code: code, detail: 'Onion rings')]),
          ),
        ],
      );
      addTearDownContainer(container);
      if (withRecovery) {
        container
            .read(posDraftRecoveryProvider.notifier)
            .capture(
              PosDraftRecovery(
                draft: const CartDraftSnapshot(
                  currencyCode: 'ILS',
                  lines: [
                    CartDraftLine(
                      menuItemId: 'burger-1',
                      name: 'Classic burger',
                      basePriceMinor: 4200,
                      quantity: 1,
                    ),
                  ],
                ),
                orderType: OrderType.takeaway,
                outboxEntryId: 'e1',
                // Bind to the SAME context the confirmation computes (the demo scope
                // key + null PIN session) — exactly how the real capture site does.
                binding: container.read(posRecoveryBindingProvider),
              ),
            );
      }
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: restoflowLocalizationsDelegates,
            supportedLocales: kSupportedLocales,
            home: Scaffold(
              body: OrderConfirmation(order: _order, onNewOrder: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('a rejected item_unavailable order shows recovery actions and '
        'NO payment', (tester) async {
      final container = await pump(
        tester,
        OutboxSyncState.rejected,
        code: 'item_unavailable',
      );
      expect(find.byKey(const Key('recovery-actions')), findsOneWidget);
      expect(find.byKey(const Key('recovery-back-to-cart')), findsOneWidget);
      expect(find.byKey(const Key('pay-cash-button')), findsNothing);
      expect(find.byKey(const Key('pay-later-button')), findsNothing);

      // Back to cart restores the draft exactly once and — MENU-ORDER-001
      // correction-window durability — RETAINS the durable recovery (Back to cart is
      // not terminal; the record is cleared only on the corrected order's acceptance
      // or an explicit discard), marking the cart as correcting THIS recovery.
      await tester.tap(find.byKey(const Key('recovery-back-to-cart')));
      await tester.pump();
      expect(container.read(cartControllerProvider).lines.length, 1);
      expect(
        container.read(posDraftRecoveryProvider).containsKey('e1'),
        isTrue,
      );
      expect(
        container.read(posActiveCorrectionSourceProvider)?.sourceOutboxEntryId,
        'e1',
      );
    });

    testWidgets('an ACCEPTED (applied) order shows payment and NO recovery '
        '(accepted-order immunity)', (tester) async {
      await pump(tester, OutboxSyncState.applied);
      expect(find.byKey(const Key('recovery-actions')), findsNothing);
      expect(find.byKey(const Key('pay-cash-button')), findsOneWidget);
    });
  });
}
