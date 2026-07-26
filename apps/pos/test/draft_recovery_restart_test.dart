import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart'
    show OrderType, sortByMenuPrintOrder;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/data/draft_recovery_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/draft_recovery_controller.dart';
import 'package:restoflow_pos/src/state/pos_session.dart'
    show posSignedInEmployeeProfileIdProvider;
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MENU-ORDER-001 (Codex #1/#3): the durable recovery must be owned by the STABLE
/// worker + scope identity, NOT the ephemeral pinSessionId — so the SAME worker
/// reclaims it after an app restart + a NEW PIN login (a new pinSessionId), while a
/// different worker or a different branch/station cannot. Uses the real provider +
/// SharedPrefs store wiring and the real JSON round-trip.

const _scopeA = PosSyncScope(
  organizationId: 'orgA',
  restaurantId: 'restA',
  branchId: 'branchA',
  deviceId: 'dev1',
);
const _scopeOtherBranch = PosSyncScope(
  organizationId: 'orgA',
  restaurantId: 'restA',
  branchId: 'branchB', // different branch => different scopeKey
  deviceId: 'dev1',
);

CartDraftSnapshot _draft() => const CartDraftSnapshot(
  currencyCode: 'ILS',
  lines: [
    CartDraftLine(
      lineId: 'line-3',
      menuItemId: 'cola-1',
      name: 'Cola',
      basePriceMinor: 1000,
      categoryDisplayOrder: 3,
      itemDisplayOrder: 2,
      quantity: 1,
    ),
    CartDraftLine(
      lineId: 'line-5',
      menuItemId: 'burger-9',
      name: 'Burger',
      basePriceMinor: 4200,
      categoryDisplayOrder: 1,
      itemDisplayOrder: 1,
      quantity: 2,
    ),
  ],
);

/// A container standing in for ONE app process: a specific worker signed in under
/// [scope], sharing the durable [store].
ProviderContainer _process({
  required PosDraftRecoveryStore store,
  required PosSyncScope scope,
  required String employeeProfileId,
}) {
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
      posDraftRecoveryStoreProvider.overrideWithValue(store),
      posSyncScopeProvider.overrideWithValue(scope),
    ],
  );
  c.read(posSignedInEmployeeProfileIdProvider.notifier).set(employeeProfileId);
  return c;
}

Future<void> _tick() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  test('the SAME worker reclaims a persisted recovery after restart + a NEW PIN '
      'login (pinSessionId is NOT the durable owner)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final store = SharedPrefsDraftRecoveryStore(prefs);

    // --- Process A: worker emp-A signs in (PIN session S1) and captures a
    //     recovery bound to the REAL current binding.
    final a = _process(
      store: store,
      scope: _scopeA,
      employeeProfileId: 'emp-A',
    );
    final bindingA = a.read(posRecoveryBindingProvider);
    // The durable binding carries the stable worker id + scope — NOT a session.
    expect(bindingA.employeeProfileId, 'emp-A');
    expect(bindingA.scopeKey, _scopeA.key);
    expect(bindingA.toJson().containsKey('pin_session_id'), isFalse);

    a.read(posDraftRecoveryProvider); // instantiate the controller
    a
        .read(posDraftRecoveryProvider.notifier)
        .capture(
          PosDraftRecovery(
            draft: _draft(),
            orderType: OrderType.takeaway,
            outboxEntryId: 'e1',
            binding: bindingA,
          ),
        );
    await _tick();
    a.dispose(); // process A dies (restart)

    // --- Process B: the SAME worker emp-A signs in again — a brand-new PIN
    //     session S2 (S1 != S2), same till. A fresh container + store.
    final b = _process(
      store: SharedPrefsDraftRecoveryStore(prefs),
      scope: _scopeA,
      employeeProfileId: 'emp-A',
    );
    addTearDown(b.dispose);
    b.read(posDraftRecoveryProvider); // triggers rehydrate
    await _tick();

    final currentBinding = b.read(posRecoveryBindingProvider);
    final reclaimed = b
        .read(posDraftRecoveryProvider.notifier)
        .recoverable('e1', currentBinding);
    expect(
      reclaimed,
      isNotNull,
      reason: 'same worker + same scope reclaims across a restart + new PIN',
    );

    // Restore to cart -> the STABLE line ids survive and it prints in menu order.
    final cart = b.read(cartControllerProvider.notifier);
    cart.restoreDraft(reclaimed!.draft);
    final restored = b.read(cartControllerProvider);
    expect(
      restored.lines.map((l) => l.lineId).toList(),
      const ['line-3', 'line-5'],
      reason: 'original line ids preserved (no re-minting, no duplicates)',
    );
    final view = cart.viewFromDraft(draft: reclaimed.draft);
    final ordered = sortByMenuPrintOrder(
      view.lines,
      (l) => [l.categoryDisplayOrder, l.itemDisplayOrder, l.linePosition],
    );
    expect([for (final l in ordered) l.name], const ['Burger', 'Cola']);
  });

  test('a DIFFERENT worker on the same till cannot reclaim it', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final store = SharedPrefsDraftRecoveryStore(prefs);

    final a = _process(
      store: store,
      scope: _scopeA,
      employeeProfileId: 'emp-A',
    );
    a.read(posDraftRecoveryProvider);
    a
        .read(posDraftRecoveryProvider.notifier)
        .capture(
          PosDraftRecovery(
            draft: _draft(),
            orderType: OrderType.takeaway,
            outboxEntryId: 'e1',
            binding: a.read(posRecoveryBindingProvider),
          ),
        );
    await _tick();
    a.dispose();

    // Worker emp-B signs in on the SAME till.
    final b = _process(
      store: SharedPrefsDraftRecoveryStore(prefs),
      scope: _scopeA,
      employeeProfileId: 'emp-B',
    );
    addTearDown(b.dispose);
    b.read(posDraftRecoveryProvider);
    await _tick();
    expect(
      b
          .read(posDraftRecoveryProvider.notifier)
          .recoverable('e1', b.read(posRecoveryBindingProvider)),
      isNull,
      reason: 'a different worker (employeeProfileId) can never restore it',
    );
  });

  test(
    'the same worker in a DIFFERENT branch/station cannot reclaim it',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPrefsDraftRecoveryStore(prefs);

      final a = _process(
        store: store,
        scope: _scopeA,
        employeeProfileId: 'emp-A',
      );
      a.read(posDraftRecoveryProvider);
      a
          .read(posDraftRecoveryProvider.notifier)
          .capture(
            PosDraftRecovery(
              draft: _draft(),
              orderType: OrderType.takeaway,
              outboxEntryId: 'e1',
              binding: a.read(posRecoveryBindingProvider),
            ),
          );
      await _tick();
      a.dispose();

      // emp-A signs in, but the till is now paired to another branch.
      final b = _process(
        store: SharedPrefsDraftRecoveryStore(prefs),
        scope: _scopeOtherBranch,
        employeeProfileId: 'emp-A',
      );
      addTearDown(b.dispose);
      b.read(posDraftRecoveryProvider);
      await _tick();
      expect(
        b
            .read(posDraftRecoveryProvider.notifier)
            .recoverable('e1', b.read(posRecoveryBindingProvider)),
        isNull,
        reason: 'a different branch/station scope can never restore it',
      );
    },
  );
}
