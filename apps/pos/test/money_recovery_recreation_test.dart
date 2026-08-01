import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
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

/// MONEY-RELEASE-PROOF-003E — the FULL SharedPreferences process-recreation
/// proof for draft recovery, with a corrupt sibling alongside the valid record.
///
/// WHAT WAS MISSING. `draft_recovery_restart_test` already disposes a container
/// and rebuilds over the same SharedPreferences, and `money_durable_stores_test`
/// already proves the store quarantines an unreadable record. Neither did both
/// AT ONCE: nothing showed that a corrupt sibling survives a real restart
/// byte-for-byte WHILE the valid record still restores completely, with its
/// configured money intact.
///
/// Everything below uses REAL production seams: the real
/// `SharedPrefsDraftRecoveryStore`, the real `PosDraftRecoveryController`
/// rehydrate-on-build, the real binding gate, and the real transactional
/// `CartController.restoreDraft`. The "process restart" is a genuine container
/// dispose + rebuild over the SAME SharedPreferences instance — never a
/// toJson/fromJson round trip.
///
/// SCOPE, STATED HONESTLY. This drives the controller + cart action, not the
/// `PosRecoveryCoordinator` dialog (which needs a BuildContext and a non-empty
/// cart to reach its Replace / Keep-current choice). That dialog path is owned
/// by `durable_recovery_e2e_test` and `addition_cart_lock_test` group J; this
/// suite deliberately does not re-claim it.
///
/// MONEY FIXTURE, independent literals: base 4500, paid modifier 1500,
/// quantity 2. 4500 + 1500 = 6000 per unit; 6000 x 2 = 12000.
const kBase = 4500;
const kDelta = 1500;
const kLineTotal = 12000;
const kSecondLine = 1000;
const kSubtotal = 13000; // 12000 + 1000, written out

const _scope = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  deviceId: 'dev-1',
);

const _prefsKey = 'restoflow.pos.draft_recovery.v1';

const _meat = SelectedModifier(
  optionId: 'opt-240',
  modifierGroupId: 'grp-meat',
  groupName: 'Meat',
  optionName: '240g',
  priceDeltaMinor: kDelta,
);

/// Two lines, one carrying a paid modifier at quantity 2, with notes, prep and
/// Dashboard display ranks — everything a real recovered cart holds.
CartDraftSnapshot _draft() => const CartDraftSnapshot(
  currencyCode: 'ILS',
  lines: [
    CartDraftLine(
      lineId: 'line-A',
      menuItemId: 'burger-9',
      name: 'Burger',
      basePriceMinor: kBase,
      quantity: 2,
      modifiers: [_meat],
      note: 'no onions',
      categoryDisplayOrder: 1,
      itemDisplayOrder: 1,
    ),
    CartDraftLine(
      lineId: 'line-B',
      menuItemId: 'cola-1',
      name: 'Cola',
      basePriceMinor: kSecondLine,
      quantity: 1,
      categoryDisplayOrder: 3,
      itemDisplayOrder: 2,
    ),
  ],
);

ProviderContainer _process(SharedPreferences prefs) {
  final c = ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: true),
      ),
      posDraftRecoveryStoreProvider.overrideWithValue(
        SharedPrefsDraftRecoveryStore(prefs),
      ),
      posSyncScopeProvider.overrideWithValue(_scope),
    ],
  );
  c.read(posSignedInEmployeeProfileIdProvider.notifier).set('emp-A');
  return c;
}

Future<void> _tick() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// The raw stored record this build cannot decode — a real record shape with
/// its `draft` replaced by a non-object, so `PosDraftRecovery.fromJson` throws.
const _corruptRaw = <String, Object?>{
  'outbox_entry_id': 'e-corrupt',
  'order_type': 'takeaway',
  'draft': 'not-an-object',
  'binding': <String, Object?>{},
};

Map<String, Object?> _storedRecoveries(SharedPreferences prefs) =>
    ((jsonDecode(prefs.getString(_prefsKey)!) as Map)['recoveries'] as Map)
        .cast<String, Object?>();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('A full process recreation: the valid recovery restores with exact '
      'money while the corrupt sibling survives byte-for-byte', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();

    // ---------------------------------------------------------- process ONE
    final p1 = _process(prefs);
    final binding = p1.read(posRecoveryBindingProvider);
    expect(binding.employeeProfileId, 'emp-A');

    p1.read(posDraftRecoveryProvider); // build the controller
    p1
        .read(posDraftRecoveryProvider.notifier)
        .capture(
          PosDraftRecovery(
            draft: _draft(),
            orderType: OrderType.takeaway,
            outboxEntryId: 'e-valid',
            binding: binding,
            customerName: 'Dana',
          ),
        );
    await _tick();

    // A corrupt sibling lands next to it, exactly as a damaged write would.
    final withCorrupt = <String, Object?>{
      ..._storedRecoveries(prefs),
      'e-corrupt': _corruptRaw,
    };
    await prefs.setString(
      _prefsKey,
      jsonEncode(<String, Object?>{
        'version': SharedPrefsDraftRecoveryStore.schemaVersion,
        'recoveries': withCorrupt,
      }),
    );

    p1.dispose(); // ---- PROCESS DEATH: containers, controllers, store all gone

    // ---------------------------------------------------------- process TWO
    final p2 = _process(prefs);
    addTearDown(p2.dispose);
    p2.read(posDraftRecoveryProvider); // triggers the real rehydrate
    await _tick();

    final current = p2.read(posRecoveryBindingProvider);
    final reclaimed = p2
        .read(posDraftRecoveryProvider.notifier)
        .recoverable('e-valid', current);
    expect(
      reclaimed,
      isNotNull,
      reason:
          'the same worker in the same scope reclaims the record across a real '
          'restart — this is the whole point of persisting it',
    );
    expect(
      p2
          .read(posDraftRecoveryProvider.notifier)
          .recoverable('e-corrupt', current),
      isNull,
      reason: 'an unreadable record is never handed out to be restored',
    );

    // ---- RESTORE through the real transactional cart action.
    final cart = p2.read(cartControllerProvider.notifier);
    expect(cart.restoreDraft(reclaimed!.draft), CartMutationResult.applied);
    final restored = p2.read(cartControllerProvider);

    expect(
      restored.lines.map((l) => l.lineId).toList(),
      const ['line-A', 'line-B'],
      reason: 'the stable line ids survive the restart',
    );
    final burger = restored.lines.first;
    expect(burger.quantity, 2);
    expect(burger.unitPriceMinor, kBase);
    expect(burger.lineTotalMinor, kLineTotal, reason: '2 x (4500 + 1500)');
    expect(burger.note, 'no onions');
    expect(burger.modifiers.single.priceDeltaMinor, kDelta);
    expect(
      burger.modifiers.single.modifierGroupId,
      'grp-meat',
      reason: 'the LOCAL stable group identity (002C) survives persistence',
    );
    expect(restored.subtotalMinor, kSubtotal);

    // ---- The corrupt sibling is STILL on disk, byte-for-byte.
    final afterRestore = _storedRecoveries(prefs);
    expect(
      afterRestore.keys,
      contains('e-corrupt'),
      reason:
          'a record we cannot read is not a record we may destroy — it must '
          'outlive a restart AND every unrelated write',
    );
    expect(
      afterRestore['e-corrupt'],
      _corruptRaw,
      reason: 'preserved verbatim, not re-shaped by this build',
    );
  });

  test(
    'B an unrelated capture and discard never erase the corrupt sibling',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        _prefsKey: jsonEncode(<String, Object?>{
          'version': SharedPrefsDraftRecoveryStore.schemaVersion,
          'recoveries': <String, Object?>{'e-corrupt': _corruptRaw},
        }),
      });
      final prefs = await SharedPreferences.getInstance();

      final p = _process(prefs);
      addTearDown(p.dispose);
      final binding = p.read(posRecoveryBindingProvider);
      p.read(posDraftRecoveryProvider);
      await _tick();

      // An UNRELATED recovery is captured, then explicitly discarded.
      p
          .read(posDraftRecoveryProvider.notifier)
          .capture(
            PosDraftRecovery(
              draft: _draft(),
              orderType: OrderType.takeaway,
              outboxEntryId: 'e-other',
              binding: binding,
            ),
          );
      await _tick();
      expect(
        await p
            .read(posDraftRecoveryProvider.notifier)
            .discardOwned('e-other', binding),
        isTrue,
      );
      await _tick();

      final stored = _storedRecoveries(prefs);
      expect(stored.keys, contains('e-corrupt'));
      expect(stored['e-corrupt'], _corruptRaw);
      expect(
        stored.keys,
        isNot(contains('e-other')),
        reason:
            'the explicitly discarded record IS removed — only the '
            'unreadable one is protected',
      );
    },
  );

  test('C the unreadable record is reported, not silently swallowed', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      _prefsKey: jsonEncode(<String, Object?>{
        'version': SharedPrefsDraftRecoveryStore.schemaVersion,
        'recoveries': <String, Object?>{'e-corrupt': _corruptRaw},
      }),
    });
    final prefs = await SharedPreferences.getInstance();
    final store = SharedPrefsDraftRecoveryStore(prefs);

    expect(await store.load(), isEmpty, reason: 'it cannot be interpreted');
    expect(
      store.unreadableRecordCount(''),
      1,
      reason:
          'the operator surface counts it, so a till holding records it cannot '
          'act on never looks identical to a healthy one (003B)',
    );
  });
}
