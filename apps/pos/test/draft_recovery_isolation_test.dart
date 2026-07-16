import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/draft_recovery_controller.dart';

/// PILOT-OPERATIONS-CORRECTIONS-001 — A2 regressions.
///
/// Draft recovery is now MULTI-SLOT (a map keyed by outbox entry id) and
/// SCOPE-BOUND (each record carries the exact scope + PIN session it may be restored
/// in). These tests exercise the seam directly: independence of two pending submits,
/// binding-gated restore, exact-once restore, and full state restoration.

const _emptyDraft = CartDraftSnapshot(
  currencyCode: 'ILS',
  lines: <CartDraftLine>[],
);

PosDraftRecovery _rec(
  String entryId, {
  PosRecoveryBinding binding = const PosRecoveryBinding(),
  String? customerName,
  CartDraftSnapshot draft = _emptyDraft,
  OrderType orderType = OrderType.takeaway,
}) => PosDraftRecovery(
  draft: draft,
  orderType: orderType,
  outboxEntryId: entryId,
  binding: binding,
  customerName: customerName,
);

const _demoBinding = PosRecoveryBinding();
const _branchA = PosRecoveryBinding(
  scopeKey: 'orgA.restA.branchA.dev1',
  pinSessionId: 'pin-emp-A',
);
const _branchB = PosRecoveryBinding(
  scopeKey: 'orgA.restA.branchB.dev1',
  pinSessionId: 'pin-emp-A',
);
const _empBOnA = PosRecoveryBinding(
  scopeKey: 'orgA.restA.branchA.dev1',
  pinSessionId: 'pin-emp-B',
);

void main() {
  group('A2 multi-slot independence', () {
    test('1. submit A and submit B each keep an independent record', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(posDraftRecoveryProvider.notifier);
      n.capture(_rec('A'));
      n.capture(_rec('B'));
      final map = c.read(posDraftRecoveryProvider);
      expect(map.keys, containsAll(<String>['A', 'B']));
    });

    test('4/5. clearing A clears only A', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(posDraftRecoveryProvider.notifier);
      n.capture(_rec('A'));
      n.capture(_rec('B'));
      n.clear('A');
      final map = c.read(posDraftRecoveryProvider);
      expect(map.containsKey('A'), isFalse);
      expect(map.containsKey('B'), isTrue);
    });

    test(
      '2/3. recoverable returns the record for the requested entry only',
      () {
        final c = ProviderContainer();
        addTearDown(c.dispose);
        final n = c.read(posDraftRecoveryProvider.notifier);
        n.capture(_rec('A', customerName: 'Alice'));
        n.capture(_rec('B', customerName: 'Bob'));
        expect(n.recoverable('A', _demoBinding)?.customerName, 'Alice');
        expect(n.recoverable('B', _demoBinding)?.customerName, 'Bob');
        expect(n.recoverable('missing', _demoBinding), isNull);
      },
    );
  });

  group('A2 scope / employee binding', () {
    test('12. a different PIN session cannot restore the record', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(posDraftRecoveryProvider.notifier);
      n.capture(_rec('A', binding: _branchA));
      // Employee A owns it; employee B (new PIN) on the same device cannot see it.
      expect(n.recoverable('A', _empBOnA), isNull);
      // The rightful owner still can.
      expect(n.recoverable('A', _branchA), isNotNull);
    });

    test('13. a branch/scope switch makes the prior recovery inaccessible', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(posDraftRecoveryProvider.notifier);
      n.capture(_rec('A', binding: _branchA));
      expect(n.recoverable('A', _branchB), isNull);
    });

    test('a demo recovery never leaks into a real paired context', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(posDraftRecoveryProvider.notifier);
      n.capture(_rec('A', binding: _demoBinding));
      expect(n.recoverable('A', _branchA), isNull);
      expect(n.recoverable('A', _demoBinding), isNotNull);
    });

    test('PosRecoveryBinding matches only on an EXACT scope + PIN', () {
      expect(_branchA.matches(_branchA), isTrue);
      expect(_branchA.matches(_branchB), isFalse);
      expect(_branchA.matches(_empBOnA), isFalse);
      expect(_demoBinding.matches(_demoBinding), isTrue);
    });

    test('Finding 2: hasRecoveryFor is true for a record under ANY binding (guards '
        'orphan dismissal), false only when truly absent', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(posDraftRecoveryProvider.notifier);
      n.capture(_rec('A', binding: _branchA));
      // Held under employee A's binding — present regardless of who asks. This is the
      // signal that fail-closes discardOrphanShell against ANOTHER session's shell.
      expect(n.hasRecoveryFor('A'), isTrue);
      // Truly absent — the ONLY case a rejected shell may be dismissed as an orphan.
      expect(n.hasRecoveryFor('missing'), isFalse);
      expect(n.hasRecoveryFor(null), isFalse);
      // ...and it is NOT recoverable by a different PIN session, which is exactly why
      // the shell must survive rather than be discarded by that other session.
      expect(n.recoverable('A', _empBOnA), isNull);
    });
  });

  group('A2 complete restoration + exact-once', () {
    const _burger = DemoMenuItemStub();

    test('10/11. restore rebuilds items, quantities, modifiers, notes', () {
      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: true),
          ),
        ],
      );
      addTearDown(c.dispose);
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItem(_burger.item);
      cart.addItem(_burger.item); // qty 2
      cart.addItemWithModifiers(
        const DemoMenuItemStub(id: 'fries-1', name: 'Fries', price: 1500).item,
        const [
          SelectedModifier(
            optionId: 'o1',
            groupName: 'Extras',
            optionName: 'Cheese',
            priceDeltaMinor: 300,
          ),
        ],
        note: 'no salt',
      );
      final draft = cart.captureDraft();
      cart.clear();
      cart.restoreDraft(draft);
      final restored = c.read(cartControllerProvider);
      expect(restored.lines.length, 2);
      final b = restored.lines.firstWhere((l) => l.menuItemId == 'burger-1');
      expect(b.quantity, 2);
      final f = restored.lines.firstWhere((l) => l.menuItemId == 'fries-1');
      expect(f.note, 'no salt');
      expect(f.modifiers.single.optionName, 'Cheese');
    });

    test('14. restoring the same draft twice never duplicates lines', () {
      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: true),
          ),
        ],
      );
      addTearDown(c.dispose);
      final cart = c.read(cartControllerProvider.notifier);
      cart.addItem(_burger.item);
      final draft = cart.captureDraft();
      cart.clear();
      cart.restoreDraft(draft);
      cart.restoreDraft(draft);
      expect(c.read(cartControllerProvider).lines.length, 1);
    });
  });
}

/// A tiny helper so the test file does not depend on the demo menu data.
class DemoMenuItemStub {
  const DemoMenuItemStub({
    this.id = 'burger-1',
    this.name = 'Classic burger',
    this.price = 4200,
  });
  final String id;
  final String name;
  final int price;
  DemoMenuItem get item => DemoMenuItem(
    id: id,
    name: name,
    priceMinor: price,
    categoryId: 'c',
    categoryName: 'C',
  );
}
