// POS-OFFLINE-OPERATIONS-002 — scope isolation + blocked actions offline.
//
// Covers OFFLINE-ARCH-SPEC tests 33, 35:
//   33 — logout / re-pair invalidates the offline continuity records, and
//        NOTHING crosses a scope: an explicit sign-out destroys the stored
//        PIN session; a re-paired till (a NEW device session) can never
//        resurrect the old pairing's session; the operational snapshot of one
//        scope is never served to another — not even as a byte-for-byte copy
//        planted under the other scope's key (the embedded-scope check reads
//        it as ABSENT, so no stale tenant data is ever sold from);
//   35 — while the POS operates from the offline snapshot every server-backed
//        action entry point — cash payment, discount, void/cancel, shift
//        close — refuses with the ONE localized snackbar instead of opening a
//        sheet whose confirm can only fail; online, the same entry points
//        open normally (the gate never overblocks).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodCall, MethodChannel;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart'
    show DeviceContext;
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_domain/restoflow_domain.dart' show OrderType;
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart'
    show RuntimeConfig, runtimeConfigProvider;
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/operational_snapshot_store.dart';
import 'package:restoflow_pos/src/data/order_identity.dart';
import 'package:restoflow_pos/src/data/recent_order.dart';
import 'package:restoflow_pos/src/data/secure_session_store.dart';
import 'package:restoflow_pos/src/data/sync_cursor_store.dart'
    show PosSyncScope;
import 'package:restoflow_pos/src/state/pos_menu_provider.dart'
    show PosMenuData;
import 'package:restoflow_pos/src/data/demo_menu.dart' show DemoMenuItem;
import 'package:restoflow_pos/src/state/pos_offline_state.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';
import 'package:restoflow_pos/src/state/submitted_order_view.dart';
import 'package:restoflow_pos/src/widgets/cancel_order_sheet.dart';
import 'package:restoflow_pos/src/widgets/cash_payment_sheet.dart';
import 'package:restoflow_pos/src/widgets/device_settings_menu.dart';
import 'package:restoflow_pos/src/widgets/discount_sheet.dart';
import 'package:restoflow_pos/src/widgets/shift_close_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

const _scopeA = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  deviceId: 'dev-1',
);
const _scopeB = PosSyncScope(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-2',
  deviceId: 'dev-1',
);

const _device = DeviceContext(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  deviceId: 'dev-1',
  deviceType: 'pos',
  deviceSessionId: 'ds-1',
);

/// The SAME till after a re-pair: identical operational scope, but the pairing
/// itself (the device session) is NEW.
const _rePairedDevice = DeviceContext(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  deviceId: 'dev-1',
  deviceType: 'pos',
  deviceSessionId: 'ds-2',
);

final class _AuthTransport implements SyncRpcTransport {
  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'start_pin_session') return 'pin-1';
    return <String, dynamic>{'ok': true, 'results': <dynamic>[]};
  }
}

PosOperationalSnapshot _snapshot(PosSyncScope scope) => PosOperationalSnapshot(
  organizationId: scope.organizationId,
  restaurantId: scope.restaurantId,
  branchId: scope.branchId,
  deviceId: scope.deviceId,
  menu: const PosMenuData(
    currencyCode: 'ILS',
    categories: [],
    items: [
      DemoMenuItem(
        id: 'item-burger',
        name: 'Burger',
        priceMinor: 4200,
        categoryId: 'cat',
        categoryName: 'Mains',
      ),
    ],
  ),
  fetchedAt: DateTime.utc(2026, 8, 6, 9),
  restaurantName: 'Shawarma HaCarmel',
  branchName: 'Branch ${scope.branchId}',
  capabilities: const <String, Object?>{'apply_discount': true},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('spec test 33 — logout/re-pair invalidates; cross-scope is never '
      'served', () {
    late Map<String, String> secure;

    setUp(() {
      secure = <String, String>{};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (MethodCall call) async {
            final args = (call.arguments as Map?)?.cast<String, Object?>();
            final key = args?['key'] as String?;
            switch (call.method) {
              case 'read':
                return secure[key];
              case 'write':
                secure[key!] = args!['value']! as String;
                return null;
              case 'delete':
                secure.remove(key);
                return null;
              case 'containsKey':
                return secure.containsKey(key);
              case 'readAll':
                return Map<String, String>.of(secure);
              case 'deleteAll':
                secure.clear();
                return null;
            }
            return null;
          });
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null);
    });

    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('the operational snapshot of one scope reads as ABSENT for another — '
        'even planted byte-for-byte under the other key', () async {
      SharedPreferences.setMockInitialValues(const {});
      final prefs = await SharedPreferences.getInstance();
      final store = SharedPrefsOperationalSnapshotStore(
        prefs: () async => prefs,
      );
      await store.save(_scopeA, _snapshot(_scopeA));

      expect(await store.load(_scopeA), isA<PosOperationalSnapshotLoaded>());
      // A DIFFERENT scope simply has no snapshot — nothing leaks across.
      expect(await store.load(_scopeB), isA<PosOperationalSnapshotAbsent>());

      // The copied-bytes attack: plant scope A's ENTIRE envelope under scope
      // B's storage key. The embedded scope ids disagree with the requested
      // scope, so it reads as ABSENT — stale tenant data is never served —
      // while the bytes themselves are not destroyed (a load never writes).
      final aBytes = prefs.getString(operationalSnapshotStorageKey(_scopeA))!;
      await prefs.setString(operationalSnapshotStorageKey(_scopeB), aBytes);
      expect(await store.load(_scopeB), isA<PosOperationalSnapshotAbsent>());
      expect(
        prefs.getString(operationalSnapshotStorageKey(_scopeB)),
        aBytes,
        reason: 'a load never writes — the evidence survives verbatim',
      );
      // And scope A itself still loads its own snapshot untouched.
      expect(await store.load(_scopeA), isA<PosOperationalSnapshotLoaded>());
    });

    test('an explicit sign-out destroys the stored PIN session, so a later '
        'offline restore finds nothing', () async {
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posAuthTransportProvider.overrideWithValue(_AuthTransport()),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(posSessionControllerProvider.notifier);
      final error = await controller.signInWithPin(
        device: _device,
        deviceId: 'dev-1',
        deviceSessionId: 'ds-1',
        employeeProfileId: 'emp-1',
        pin: '4321',
        employeeDisplayName: 'Amira K.',
      );
      expect(error, isNull);
      await settle();
      expect(
        secure[posPinSessionStorageKey(_scopeA)],
        isNotNull,
        reason: 'the online establish persisted the bounded record',
      );
      // The record never contains the PIN.
      expect(secure[posPinSessionStorageKey(_scopeA)], isNot(contains('4321')));

      controller.endSession();
      await settle();
      expect(
        secure[posPinSessionStorageKey(_scopeA)],
        isNull,
        reason: 'logout destroys the offline-continuity record',
      );
      expect(await PosSecureSessionStore(isWeb: false).read(_scopeA), isNull);
      expect(
        await controller.restoreOfflineSession(device: _device),
        PosOfflineRestoreResult.noRecord,
      );
    });

    test('a re-paired till (new device session) can never resurrect the old '
        'pairing\'s session — the record is refused AND destroyed', () async {
      final container = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posAuthTransportProvider.overrideWithValue(_AuthTransport()),
        ],
      );
      addTearDown(container.dispose);
      final controller = container.read(posSessionControllerProvider.notifier);
      final error = await controller.signInWithPin(
        device: _device,
        deviceId: 'dev-1',
        deviceSessionId: 'ds-1',
        employeeProfileId: 'emp-1',
        pin: '4321',
      );
      expect(error, isNull);
      await settle();
      // The session ends WITHOUT clearing the stored record (a crash/restart,
      // not a logout) — the record legitimately survives for ITS pairing.
      controller.endSession(clearStoredSession: false);
      await settle();
      expect(secure[posPinSessionStorageKey(_scopeA)], isNotNull);

      // The till is re-paired: same scope, NEW device session. The stored
      // record names the OLD pairing, so the restore refuses and destroys it.
      expect(
        await controller.restoreOfflineSession(device: _rePairedDevice),
        PosOfflineRestoreResult.wrongPairing,
      );
      await settle();
      expect(
        secure[posPinSessionStorageKey(_scopeA)],
        isNull,
        reason: 'a record another pairing minted can never be valid again',
      );
    });

    test('a copied session record planted under another scope\'s key is '
        'refused by the embedded-scope check', () async {
      final store = PosSecureSessionStore(isWeb: false);
      final record = PosStoredPinSession(
        sessionId: 'pin-stored',
        employeeProfileId: 'emp-1',
        organizationId: _scopeA.organizationId,
        restaurantId: _scopeA.restaurantId,
        branchId: _scopeA.branchId,
        deviceId: _scopeA.deviceId,
        deviceSessionId: 'ds-1',
        lastOnlineVerify: DateTime.utc(2026, 8, 6, 9),
      );
      await store.save(_scopeA, record);
      // Plant scope A's bytes under scope B's key (a hand-copied value).
      secure[posPinSessionStorageKey(_scopeB)] =
          secure[posPinSessionStorageKey(_scopeA)]!;
      expect(await store.read(_scopeB), isNull);
      expect(
        secure[posPinSessionStorageKey(_scopeB)],
        isNull,
        reason: 'a session record that cannot be trusted must not linger',
      );
      // Scope A's own record is untouched and still readable.
      expect(await store.read(_scopeA), isNotNull);
    });
  });

  group('spec test 35 — every server-backed entry point refuses offline', () {
    Future<(ProviderContainer, AppLocalizations)> pumpSurface(
      WidgetTester tester, {
      required bool offline,
      required Widget Function(BuildContext context, AppLocalizations l10n)
      body,
    }) async {
      SharedPreferences.setMockInitialValues(const {});
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      final container = ProviderContainer();
      addTearDown(container.dispose);
      if (offline) {
        container
            .read(posOfflineModeProvider.notifier)
            .recordOfflineCacheServed(
              snapshotFetchedAt: DateTime.utc(2026, 8, 6),
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
              appBar: AppBar(actions: const [DeviceSettingsMenu()]),
              body: Builder(builder: (context) => body(context, l10n)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (container, l10n);
    }

    PosRecentOrder recentOrder() => const PosRecentOrder(
      order: SubmittedOrderView(
        orderNumber: '#3F7A2C',
        orderType: OrderType.takeaway,
        currencyCode: 'ILS',
        subtotalMinor: 4200,
        lines: [
          SubmittedLineView(
            name: 'Burger',
            quantity: 1,
            lineTotalMinor: 4200,
            currencyCode: 'ILS',
          ),
        ],
        orderId: 'order-1',
      ),
    );

    testWidgets('cash payment: the entry refuses with the localized snackbar '
        'and no sheet opens', (tester) async {
      final (_, l10n) = await pumpSurface(
        tester,
        offline: true,
        body: (context, l10n) => ElevatedButton(
          key: const Key('open-pay'),
          onPressed: () => CashPaymentSheet.show(
            context,
            identity: PosOrderIdentity.server('order-1'),
            orderNumber: '#3F7A2C',
            amountMinor: 4200,
            currencyCode: 'ILS',
            orderId: 'order-1',
          ),
          child: const Text('pay'),
        ),
      );
      await tester.tap(find.byKey(const Key('open-pay')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CashPaymentSheet), findsNothing);
      expect(find.text(l10n.posOfflineActionUnavailable), findsOneWidget);
    });

    testWidgets('discount: the entry refuses with the localized snackbar and '
        'no sheet opens', (tester) async {
      final (_, l10n) = await pumpSurface(
        tester,
        offline: true,
        body: (context, l10n) => ElevatedButton(
          key: const Key('open-discount'),
          onPressed: () => DiscountSheet.show(
            context,
            orderId: 'order-1',
            subtotalMinor: 4200,
            taxTotalMinor: 0,
            currencyCode: 'ILS',
          ),
          child: const Text('discount'),
        ),
      );
      await tester.tap(find.byKey(const Key('open-discount')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(DiscountSheet), findsNothing);
      expect(find.text(l10n.posOfflineActionUnavailable), findsOneWidget);
    });

    testWidgets('void/cancel: the entry refuses with the localized snackbar '
        'and no sheet opens', (tester) async {
      final (_, l10n) = await pumpSurface(
        tester,
        offline: true,
        body: (context, l10n) => ElevatedButton(
          key: const Key('open-cancel'),
          onPressed: () => CancelOrderSheet.show(context, order: recentOrder()),
          child: const Text('cancel'),
        ),
      );
      await tester.tap(find.byKey(const Key('open-cancel')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CancelOrderSheet), findsNothing);
      expect(find.text(l10n.posOfflineActionUnavailable), findsOneWidget);
    });

    testWidgets('shift close: the menu item refuses with the localized '
        'snackbar and no workflow opens', (tester) async {
      final (_, l10n) = await pumpSurface(
        tester,
        offline: true,
        body: (context, l10n) => const SizedBox(),
      );
      await tester.tap(find.byKey(const Key('device-settings-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('shift-close-item')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PosShiftCloseSheet), findsNothing);
      expect(find.text(l10n.posOfflineActionUnavailable), findsOneWidget);
    });

    testWidgets('control: ONLINE the same gate opens the payment sheet — the '
        'refusal never overblocks', (tester) async {
      final (_, l10n) = await pumpSurface(
        tester,
        offline: false,
        body: (context, l10n) => ElevatedButton(
          key: const Key('open-pay'),
          onPressed: () => CashPaymentSheet.show(
            context,
            identity: PosOrderIdentity.server('order-1'),
            orderNumber: '#3F7A2C',
            amountMinor: 4200,
            currencyCode: 'ILS',
            orderId: 'order-1',
          ),
          child: const Text('pay'),
        ),
      );
      await tester.tap(find.byKey(const Key('open-pay')));
      await tester.pumpAndSettle();
      expect(find.byType(CashPaymentSheet), findsOneWidget);
      expect(find.text(l10n.posOfflineActionUnavailable), findsNothing);
    });
  });
}
