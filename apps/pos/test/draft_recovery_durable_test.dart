import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show OrderType, sortByMenuPrintOrder;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/data/draft_recovery_store.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/draft_recovery_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MENU-ORDER-001 (Codex #8/#9): a permanently-rejected order's recovery — its
/// draft WITH the Dashboard menu ranks, order type, table, customer name — must
/// survive a full app restart, so Back-to-cart resubmits in menu order even after
/// the process died. These tests exercise the REAL serialized payload (JSON via
/// shared_preferences), not an in-memory map.

/// Two lines whose Dashboard ranks are the REVERSE of insertion order.
CartDraftSnapshot _draft() => const CartDraftSnapshot(
  currencyCode: 'ILS',
  lines: [
    CartDraftLine(
      menuItemId: 'cola-1',
      name: 'Cola',
      basePriceMinor: 1000,
      quantity: 1,
      note: 'no ice',
      categoryDisplayOrder: 3,
      itemDisplayOrder: 2,
    ),
    CartDraftLine(
      menuItemId: 'burger-9',
      name: 'Burger',
      basePriceMinor: 4200,
      quantity: 2,
      categoryDisplayOrder: 1,
      itemDisplayOrder: 1,
    ),
  ],
);

void main() {
  test(
    'a captured recovery survives a store restart with its Dashboard menu ranks '
    '(real JSON round-trip)',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      // Session A: persist the recovery through the REAL SharedPrefs store.
      final storeA = SharedPrefsDraftRecoveryStore(prefs);
      await storeA.persist(<String, PosDraftRecovery>{
        'e1': PosDraftRecovery(
          draft: _draft(),
          orderType: OrderType.takeaway,
          outboxEntryId: 'e1',
          binding: const PosRecoveryBinding(),
          customerName: 'Dana',
        ),
      });

      // FULL RESTART: a brand-new store over the SAME durable prefs.
      final storeB = SharedPrefsDraftRecoveryStore(prefs);
      final loaded = await storeB.load();

      expect(loaded.containsKey('e1'), isTrue);
      final recovered = loaded['e1']!;
      expect(recovered.customerName, 'Dana');
      expect(recovered.orderType, OrderType.takeaway);

      final cola = recovered.draft.lines.firstWhere(
        (l) => l.menuItemId == 'cola-1',
      );
      final burger = recovered.draft.lines.firstWhere(
        (l) => l.menuItemId == 'burger-9',
      );
      // The Dashboard menu ranks + note + quantity all survived the restart.
      expect((cola.categoryDisplayOrder, cola.itemDisplayOrder), (3, 2));
      expect(cola.note, 'no ice');
      expect((burger.categoryDisplayOrder, burger.itemDisplayOrder), (1, 1));
      expect(burger.quantity, 2);
    },
  );

  test('the RECOVERED draft builds a submitted view in DASHBOARD order '
      '(Burger before Cola), not cart order', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await SharedPrefsDraftRecoveryStore(
      prefs,
    ).persist(<String, PosDraftRecovery>{
      'e1': PosDraftRecovery(
        draft: _draft(),
        orderType: OrderType.takeaway,
        outboxEntryId: 'e1',
        binding: const PosRecoveryBinding(),
      ),
    });
    final recovered = (await SharedPrefsDraftRecoveryStore(
      prefs,
    ).load())['e1']!;

    final container = ProviderContainer(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: true),
        ),
      ],
    );
    addTearDown(container.dispose);
    final cart = container.read(cartControllerProvider.notifier);

    final view = cart.viewFromDraft(draft: recovered.draft);
    // The receipt/kitchen builders order by (category, item, line_position) via
    // this same canonical sort — so a recovered order prints in menu order.
    final ordered = sortByMenuPrintOrder(
      view.lines,
      (l) => [l.categoryDisplayOrder, l.itemDisplayOrder, l.linePosition],
    );
    expect([for (final l in ordered) l.name], const ['Burger', 'Cola']);
  });

  test(
    'the durable store round-trips a full app/controller restart via the provider '
    '(capture -> new container loads it)',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPrefsDraftRecoveryStore(prefs);

      // Session A: a real controller captures a recovery, which persists it.
      final a = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: true),
          ),
          posDraftRecoveryStoreProvider.overrideWithValue(store),
        ],
      );
      a.read(posDraftRecoveryProvider); // instantiate the controller
      a
          .read(posDraftRecoveryProvider.notifier)
          .capture(
            PosDraftRecovery(
              draft: _draft(),
              orderType: OrderType.takeaway,
              outboxEntryId: 'e1',
              binding: const PosRecoveryBinding(),
            ),
          );
      // Let the fire-and-forget persist land.
      await Future<void>.delayed(Duration.zero);
      a.dispose(); // DESTROY session A entirely.

      // Session B: a brand-new container + controller over the SAME durable store
      // rehydrates the recovery on build.
      final b = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: true),
          ),
          posDraftRecoveryStoreProvider.overrideWithValue(
            SharedPrefsDraftRecoveryStore(prefs),
          ),
        ],
      );
      addTearDown(b.dispose);
      b.read(posDraftRecoveryProvider); // triggers _load()
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final map = b.read(posDraftRecoveryProvider);
      expect(
        map.containsKey('e1'),
        isTrue,
        reason: 'recovery rehydrated on restart',
      );
      final burger = map['e1']!.draft.lines.firstWhere(
        (l) => l.menuItemId == 'burger-9',
      );
      expect((burger.categoryDisplayOrder, burger.itemDisplayOrder), (1, 1));
    },
  );
}
