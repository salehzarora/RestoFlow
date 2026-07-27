import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_data_remote/restoflow_data_remote.dart'
    show SyncRpcTransport;
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_pos/src/data/draft_recovery_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/state/cart_controller.dart';
import 'package:restoflow_pos/src/state/draft_recovery_controller.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/pos_sync_scope_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// MENU-ORDER-001 (Codex 4th pass, #7 + #8): PRODUCTION-LIKE durable-recovery
/// proofs driven through the REAL sign-in seam — [PosSessionController.signInWithPin]
/// over a fake [SyncRpcTransport] that mints a fresh `start_pin_session` id each call
/// — NOT by injecting the worker-id provider directly. Proves:
///   * #7: the SAME worker reclaims a persisted recovery across an app restart + a
///     brand-new PIN session (S1 != S2), because ownership is the STABLE
///     employeeProfileId (+ scopeKey), never the ephemeral pinSessionId;
///   * #8: with NO worker signed in the recovery is invisible/unrestorable; a wrong
///     worker (B) can never see it; the correct worker (A) makes it visible again;
///     signing out HIDES it without DELETING it (A can still reclaim on the next
///     sign-in) and never touches another worker's record.

const _scopeA = PosSyncScope(
  organizationId: 'orgA',
  restaurantId: 'restA',
  branchId: 'branchA',
  deviceId: 'dev1',
);
const _deviceA = DeviceContext(
  organizationId: 'orgA',
  restaurantId: 'restA',
  branchId: 'branchA',
  deviceId: 'dev1',
  deviceSessionId: 'devsess-A',
);

/// A transport that returns the NEXT queued pin-session id for each
/// `start_pin_session`, an APPLIED shift.open for the best-effort bootstrap, and a
/// benign null for everything else (the shift summary read fails soft).
class _SeqTransport implements SyncRpcTransport {
  _SeqTransport(this._pinSessionIds);
  final List<String> _pinSessionIds;
  int _i = 0;
  final List<String> startedPinSessions = <String>[];

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'start_pin_session') {
      final id = _pinSessionIds[_i++];
      startedPinSessions.add(id);
      return id;
    }
    if (function == 'sync_push') {
      return <String, dynamic>{
        'ok': true,
        'results': <dynamic>[
          <String, dynamic>{
            'operation_type': 'shift.open',
            'status': 'applied',
            'ok': true,
          },
        ],
      };
    }
    return null; // get_open_shift_summary etc. -> fail-soft
  }
}

/// One app "process": a fresh container over the durable [store], with a fake
/// transport that will mint [pinSessionIds] in order. No session yet.
ProviderContainer _process({
  required PosDraftRecoveryStore store,
  required PosSyncScope scope,
  required List<String> pinSessionIds,
}) {
  return ProviderContainer(
    overrides: [
      runtimeConfigProvider.overrideWithValue(
        RuntimeConfig.test(isDemoMode: false),
      ),
      posAuthTransportProvider.overrideWithValue(_SeqTransport(pinSessionIds)),
      // No dart-define config -> build() resolves to null; we sign in manually.
      posRealSessionConfigProvider.overrideWithValue(null),
      posDraftRecoveryStoreProvider.overrideWithValue(store),
      posSyncScopeProvider.overrideWithValue(scope),
    ],
  );
}

/// Drives the REAL PIN sign-in and returns the established pinSessionId.
Future<String> _signIn(
  ProviderContainer c, {
  required String employeeProfileId,
}) async {
  final controller = c.read(posSessionControllerProvider.notifier);
  await c.read(posSessionControllerProvider.future); // build() -> null
  final err = await controller.signInWithPin(
    device: _deviceA,
    deviceId: _deviceA.deviceId!,
    deviceSessionId: _deviceA.deviceSessionId!,
    employeeProfileId: employeeProfileId,
    pin: 'verifier',
  );
  expect(err, isNull, reason: 'the fake transport starts a PIN session');
  await pumpEventQueue(); // let the best-effort shift bootstrap settle
  return c.read(posSyncSessionProvider)!.pinSessionId;
}

CartDraftSnapshot _draft() => const CartDraftSnapshot(
  currencyCode: 'ILS',
  lines: [
    CartDraftLine(
      lineId: 'line-3',
      menuItemId: 'cola-1',
      name: 'Cola',
      basePriceMinor: 1000,
      quantity: 1,
    ),
  ],
);

PosDraftRecovery _recovery(PosRecoveryBinding binding) => PosDraftRecovery(
  draft: _draft(),
  orderType: OrderType.takeaway,
  outboxEntryId: 'e1',
  binding: binding,
);

void main() {
  test(
    '#7 the SAME worker reclaims a persisted recovery through a REAL restart + '
    'a NEW PIN session (S1 != S2); pinSessionId is NOT the ownership key',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      // --- Process A: real sign-in (PIN session S1) publishes the STABLE worker id.
      final a = _process(
        store: SharedPrefsDraftRecoveryStore(prefs),
        scope: _scopeA,
        pinSessionIds: ['S1'],
      );
      final s1 = await _signIn(a, employeeProfileId: 'emp-A');
      expect(a.read(posSignedInEmployeeProfileIdProvider), 'emp-A');

      final bindingA = a.read(posRecoveryBindingProvider);
      expect(bindingA.scopeKey, _scopeA.key);
      expect(bindingA.employeeProfileId, 'emp-A');
      expect(
        bindingA.toJson().containsKey('pin_session_id'),
        isFalse,
        reason: 'the ephemeral pinSessionId is never persisted as the owner',
      );

      a.read(posDraftRecoveryProvider); // instantiate the controller
      a.read(posDraftRecoveryProvider.notifier).capture(_recovery(bindingA));
      await pumpEventQueue(); // flush the durable persist
      a.dispose(); // process A dies (app restart)

      // --- Process B: the SAME worker signs in again -> a brand-new PIN session S2.
      final b = _process(
        store: SharedPrefsDraftRecoveryStore(prefs),
        scope: _scopeA,
        pinSessionIds: ['S2'],
      );
      addTearDown(b.dispose);
      final s2 = await _signIn(b, employeeProfileId: 'emp-A');
      expect(s2, isNot(s1), reason: 'a new PIN login mints a NEW pinSessionId');

      b.read(posDraftRecoveryProvider); // triggers rehydrate
      await pumpEventQueue();

      final reclaimed = b
          .read(posDraftRecoveryProvider.notifier)
          .recoverable('e1', b.read(posRecoveryBindingProvider));
      expect(
        reclaimed,
        isNotNull,
        reason: 'same worker + same scope reclaims across restart + S1 != S2',
      );

      // Restore to cart -> the stable line id survives (no re-mint, no duplicate).
      final cart = b.read(cartControllerProvider.notifier);
      cart.restoreDraft(reclaimed!.draft);
      expect(
        b.read(cartControllerProvider).lines.map((l) => l.lineId).toList(),
        const ['line-3'],
      );
    },
  );

  test(
    '#8 an unauthenticated device cannot see/restore the recovery; a wrong '
    'worker cannot; the correct worker can; sign-out HIDES without DELETING',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();

      // Worker A signs in and persists a recovery owned by emp-A / scopeA.
      final a = _process(
        store: SharedPrefsDraftRecoveryStore(prefs),
        scope: _scopeA,
        pinSessionIds: ['S1'],
      );
      await _signIn(a, employeeProfileId: 'emp-A');
      final bindingA = a.read(posRecoveryBindingProvider);
      a.read(posDraftRecoveryProvider);
      a.read(posDraftRecoveryProvider.notifier).capture(_recovery(bindingA));
      await pumpEventQueue();
      a.dispose();

      // Fresh device, NO worker signed in: employeeProfileId is null.
      final idle = _process(
        store: SharedPrefsDraftRecoveryStore(prefs),
        scope: _scopeA,
        pinSessionIds: ['unused'],
      );
      addTearDown(idle.dispose);
      idle.read(posDraftRecoveryProvider);
      await pumpEventQueue();
      expect(idle.read(posSignedInEmployeeProfileIdProvider), isNull);
      expect(
        idle
            .read(posDraftRecoveryProvider.notifier)
            .recoverable('e1', idle.read(posRecoveryBindingProvider)),
        isNull,
        reason: 'no signed-in worker -> the recovery is invisible/unrestorable',
      );
      // The record still EXISTS in the store (it was not leaked NOR deleted).
      expect(
        idle.read(posDraftRecoveryProvider.notifier).hasRecoveryFor('e1'),
        isTrue,
      );

      // A DIFFERENT worker (B) signs in on the same till: still invisible.
      final s2 = await _signIn(idle, employeeProfileId: 'emp-B');
      expect(s2, 'unused');
      expect(
        idle
            .read(posDraftRecoveryProvider.notifier)
            .recoverable('e1', idle.read(posRecoveryBindingProvider)),
        isNull,
        reason: 'worker B can never see worker A\'s draft',
      );

      // Sign B out, sign A back in: A reclaims it (it was hidden, not deleted).
      idle.read(posSessionControllerProvider.notifier).endSession();
      expect(idle.read(posSignedInEmployeeProfileIdProvider), isNull);

      final aAgain = _process(
        store: SharedPrefsDraftRecoveryStore(prefs),
        scope: _scopeA,
        pinSessionIds: ['S3'],
      );
      addTearDown(aAgain.dispose);
      await _signIn(aAgain, employeeProfileId: 'emp-A');
      aAgain.read(posDraftRecoveryProvider);
      await pumpEventQueue();
      expect(
        aAgain
            .read(posDraftRecoveryProvider.notifier)
            .recoverable('e1', aAgain.read(posRecoveryBindingProvider)),
        isNotNull,
        reason: 'the correct worker still reclaims it after a sign-out cycle',
      );
    },
  );
}
