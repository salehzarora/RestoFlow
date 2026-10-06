import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_dashboard/src/admin/supabase_admin_device_repository.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

class _Transport implements SyncRpcTransport {
  _Transport({this.expired = false, this.status = 'active'});
  bool expired;
  String status;
  DateTime now = DateTime.utc(2035, 1, 1, 12);
  Duration lifetime = const Duration(days: 30);
  bool metadata = true;
  bool legacyNull = false;
  int loads = 0;
  Completer<void>? loadingGate;
  final issuedFor = <String>[];
  final revokedFor = <String>[];
  DateTime? codeExpiresAt;
  bool hideDevice = false;
  bool codeExpiryMetadata = true;
  Object? loadError;
  SyncTransportException? issueError;
  Completer<void>? actionGate;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'list_devices') {
      loads++;
      await loadingGate?.future;
      if (loadError case final error?) throw error;
      return {
        'ok': true,
        if (metadata) 'server_now': now.toIso8601String(),
        'devices': [
          if (!hideDevice)
            {
              'device_id': 'existing-device',
              'label': 'Counter POS',
              'device_type': 'pos',
              'branch_label': 'Main',
              'status': status,
              'device_pairing_id': status == 'none' ? null : 'pairing',
              if (codeExpiryMetadata)
                'code_expires_at': codeExpiresAt?.toIso8601String(),
              'has_open_session':
                  !expired && status != 'revoked' && status != 'none',
              if (metadata)
                'session_expires_at': legacyNull
                    ? null
                    : (expired ? now : now.add(lifetime)).toIso8601String(),
              if (metadata)
                'last_seen_at': now
                    .subtract(const Duration(days: 1))
                    .toIso8601String(),
            },
        ],
      };
    }
    if (function == 'issue_device_enrollment_code') {
      issuedFor.add(params['p_device_id'] as String);
      await actionGate?.future;
      if (issueError case final error?) throw error;
      status = 'code_issued';
      codeExpiresAt = now.add(const Duration(minutes: 5));
      return {
        'ok': true,
        'device_id': params['p_device_id'],
        'device_pairing_id': 'replacement-pairing',
        'enrollment_code': 'test-code',
      };
    }
    if (function == 'revoke_device_management') {
      revokedFor.add(params['p_device_id'] as String);
      await actionGate?.future;
      status = 'revoked';
      return {'ok': true};
    }
    throw StateError('Unexpected RPC $function');
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Transport transport, {
  Locale locale = const Locale('en'),
  double width = 1200,
  double scale = 1,
  MembershipRole role = MembershipRole.manager,
  PairingPanelPresenter? pairingPanel,
  ProviderContainer? cachedContainer,
  bool settle = true,
  ValueNotifier<bool>? screenVisible,
}) async {
  tester.view.physicalSize = Size(width, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  final scope = AdminScope.demo.copyWith(actingRole: role);
  final app = MaterialApp(
    locale: locale,
    localizationsDelegates: restoflowLocalizationsDelegates,
    supportedLocales: kSupportedLocales,
    builder: (context, child) => MediaQuery.withClampedTextScaling(
      minScaleFactor: scale,
      maxScaleFactor: scale,
      child: child!,
    ),
    home: Scaffold(
      body: screenVisible == null
          ? const AdminDevicesScreen()
          : ValueListenableBuilder<bool>(
              valueListenable: screenVisible,
              builder: (_, visible, _) => visible
                  ? const AdminDevicesScreen()
                  : const SizedBox.shrink(),
            ),
    ),
  );
  await tester.pumpWidget(
    cachedContainer != null
        ? UncontrolledProviderScope(container: cachedContainer, child: app)
        : ProviderScope(
            overrides: [
              ...adminFeatureOverrides(
                scope: scope,
                repository: SupabaseAdminDeviceRepository(
                  transport: transport,
                  scope: scope,
                  currentUserId: () => 'manager',
                  nonce: () => 1,
                ),
              ),
              if (pairingPanel != null)
                devicePairingPanelProvider.overrideWithValue(pairingPanel),
            ],
            child: app,
          ),
  );
  if (settle) await tester.pumpAndSettle();
}

void main() {
  ProviderContainer containerFor(_Transport transport) => ProviderContainer(
    overrides: adminFeatureOverrides(
      scope: AdminScope.demo,
      repository: SupabaseAdminDeviceRepository(
        transport: transport,
        scope: AdminScope.demo,
        currentUserId: () => 'manager',
      ),
    ),
  );

  test('H6 action locks are per device and release after failure', () async {
    final transport = _Transport();
    final container = containerFor(transport);
    addTearDown(container.dispose);
    final controller = container.read(adminControllerProvider);
    final gate = Completer<void>();
    transport.actionGate = gate;
    transport.issueError = const SyncTransportException(
      SyncTransportErrorKind.server,
      code: '500',
    );
    final failedIssue = controller.issueEnrollmentCode('existing-device');
    final otherDevice = controller.revokeDevice('other-device');
    final blockedRevoke = await controller.revokeDevice('existing-device');
    expect(blockedRevoke.isSuccess, isFalse);
    expect(transport.issuedFor, ['existing-device']);
    expect(transport.revokedFor, ['other-device']);
    gate.complete();
    expect((await failedIssue).isSuccess, isFalse);
    expect((await otherDevice).isSuccess, isTrue);
    transport.issueError = null;
    expect(
      (await controller.issueEnrollmentCode('existing-device')).isSuccess,
      isTrue,
    );
    expect(transport.issuedFor, ['existing-device', 'existing-device']);
    expect(container.read(adminDeviceActionsInFlightProvider), isEmpty);
  });

  for (final expired in [false, true]) {
    testWidgets(
      'H6 failed refresh retains ${expired ? 'expired' : 'active'} tile and retries',
      (tester) async {
        final transport = _Transport(expired: expired);
        await _pump(tester, transport);
        final tile = tester.element(
          find.byKey(const ValueKey('existing-device')),
        );
        transport.loadError = StateError('offline');
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(find.text('Counter POS'), findsOneWidget);
        expect(
          tester.element(find.byKey(const ValueKey('existing-device'))),
          same(tile),
        );
        expect(find.text('Session active'), findsNothing);
        expect(find.text('Session expired'), findsNothing);
        final l10n = await AppLocalizations.delegate.load(const Locale('en'));
        expect(find.text(l10n.adminStateErrorBody), findsOneWidget);
        transport.loadError = null;
        await tester.tap(find.text(l10n.adminRetry));
        await tester.pumpAndSettle();
        expect(
          find.text(expired ? 'Session expired' : 'Session active'),
          findsOneWidget,
        );
        expect(transport.loads, 3);
      },
    );
  }

  for (final action in ['Revoke', 'New code for this device']) {
    testWidgets('H6 $action stays disabled after tile recreation during RPC', (
      tester,
    ) async {
      final transport = _Transport();
      final container = containerFor(transport);
      final visible = ValueNotifier(true);
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
        container.dispose();
        visible.dispose();
      });
      await _pump(
        tester,
        transport,
        cachedContainer: container,
        screenVisible: visible,
      );
      transport.actionGate = gate;
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(
          FilledButton,
          action == 'Revoke' ? 'Revoke' : 'Issue code',
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      visible.value = false;
      await tester.pump();
      visible.value = true;
      await tester.pump();
      await tester.pump();
      await tester.pump();
      final button = tester.widget<ButtonStyleButton>(
        find.widgetWithText(
          action == 'Revoke' ? TextButton : FilledButton,
          action,
        ),
      );
      expect(button.onPressed, isNull);
      final controller = container.read(adminControllerProvider);
      final duplicate = action == 'Revoke'
          ? controller.revokeDevice('existing-device')
          : controller.issueEnrollmentCode('existing-device');
      await tester.pump();
      expect(action == 'Revoke' ? transport.revokedFor : transport.issuedFor, [
        'existing-device',
      ]);
      expect((await duplicate).isSuccess, isFalse);
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    for (final duringRpc in [false, true]) {
      testWidgets(
        'H6 $action handles container disposal ${duringRpc ? 'during RPC' : 'before confirmation'}',
        (tester) async {
          final transport = _Transport();
          final container = containerFor(transport);
          final visible = ValueNotifier(true);
          addTearDown(visible.dispose);
          final gate = Completer<void>();
          await _pump(
            tester,
            transport,
            cachedContainer: container,
            screenVisible: visible,
          );
          await tester.tap(find.text(action));
          await tester.pumpAndSettle();
          if (duringRpc) {
            transport.actionGate = gate;
            await tester.tap(
              find.widgetWithText(
                FilledButton,
                action == 'Revoke' ? 'Revoke' : 'Issue code',
              ),
            );
            await tester.pump();
            await tester.pump(const Duration(milliseconds: 300));
          }
          visible.value = false;
          await tester.pump();
          container.dispose();
          if (duringRpc) {
            gate.complete();
          } else {
            await tester.tap(
              find.widgetWithText(
                FilledButton,
                action == 'Revoke' ? 'Revoke' : 'Issue code',
              ),
            );
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (!duringRpc) {
            expect(transport.issuedFor, isEmpty);
            expect(transport.revokedFor, isEmpty);
            final l10n = await AppLocalizations.delegate.load(
              const Locale('en'),
            );
            expect(find.text(l10n.adminActionProblem), findsOneWidget);
          }
        },
      );
    }
  }

  testWidgets('H6 confirming code for a removed device shows device removed', (
    tester,
  ) async {
    final transport = _Transport();
    await _pump(tester, transport);
    await tester.tap(find.text('New code for this device'));
    await tester.pumpAndSettle();
    transport.issueError = const SyncTransportException(
      SyncTransportErrorKind.server,
      code: '42501',
      message:
          'issue_device_enrollment_code: device not found, inactive, or its scope is soft-deleted',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Issue code'));
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.activityLogTitleDeviceRevoked), findsOneWidget);
    expect(find.text(l10n.adminActionProblem), findsNothing);
  });

  for (final status in ['code_issued', 'code_expired']) {
    testWidgets('H6 $status with expired code hides pairing hint', (
      tester,
    ) async {
      final transport = _Transport(status: status);
      transport.codeExpiresAt = transport.now;
      await _pump(tester, transport);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.adminDevStatusCodeExpired), findsOneWidget);
      expect(find.text(l10n.adminPairOnDevice), findsNothing);
    });
  }

  testWidgets(
    'H6 legacy codeIssued without expiry still offers confirmed new code',
    (tester) async {
      final transport = _Transport(status: 'code_issued')
        ..metadata = false
        ..codeExpiryMetadata = false;
      await _pump(tester, transport, pairingPanel: (_, _) async {});
      expect(find.text('New code for this device'), findsOneWidget);
      await tester.tap(find.text('New code for this device'));
      await tester.pumpAndSettle();
      expect(transport.issuedFor, isEmpty);
      await tester.tap(find.widgetWithText(FilledButton, 'Issue code'));
      await tester.pumpAndSettle();
      expect(transport.issuedFor, ['existing-device']);
    },
  );

  for (final elapsedOffscreen in [4, 8]) {
    testWidgets(
      'recreated tile retains fetch deadline after $elapsedOffscreen seconds offscreen',
      (tester) async {
        var elapsed = Duration.zero;
        final transport = _Transport()..lifetime = const Duration(seconds: 6);
        final repository = SupabaseAdminDeviceRepository(
          transport: transport,
          scope: AdminScope.demo,
          currentUserId: () => 'manager',
          snapshotClock: () => AdminDeviceSnapshotClock(elapsed: () => elapsed),
        );
        final result = await repository.loadDevices();
        final retained = result.fold((rows) => rows, (_) => <AdminDevice>[]);
        var visible = true;
        final container = ProviderContainer(
          overrides: [
            ...adminFeatureOverrides(
              scope: AdminScope.demo,
              repository: repository,
            ),
            adminDevicesProvider.overrideWith(
              (ref) async =>
                  visible ? [retained.single.copyWith()] : <AdminDevice>[],
            ),
          ],
        );
        addTearDown(container.dispose);
        await _pump(tester, transport, cachedContainer: container);
        expect(find.text('Session active'), findsOneWidget);
        visible = false;
        container.invalidate(adminDevicesProvider);
        await tester.pumpAndSettle();
        expect(find.text('Counter POS'), findsNothing);
        elapsed = Duration(seconds: elapsedOffscreen);
        visible = true;
        container.invalidate(adminDevicesProvider);
        await tester.pumpAndSettle();
        if (elapsedOffscreen < 6) {
          expect(find.text('Session active'), findsOneWidget);
          elapsed = const Duration(seconds: 6);
          await tester.pump(const Duration(seconds: 2));
          await tester.pumpAndSettle();
        }
        expect(find.text('Session active'), findsNothing);
        expect(find.text('Session expired'), findsOneWidget);
        expect(transport.loads, 1, reason: 'The same snapshot was retained.');
      },
    );
  }

  testWidgets('unused code expires while the list remains mounted', (
    tester,
  ) async {
    final transport = _Transport(status: 'code_issued');
    transport.codeExpiresAt = transport.now.add(const Duration(seconds: 2));
    await _pump(tester, transport, pairingPanel: (_, _) async {});
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.adminDevStatusCodeExpired), findsNothing);
    transport.now = transport.codeExpiresAt!;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text(l10n.adminDevStatusCodeExpired), findsOneWidget);
    expect(find.text('New code for this device'), findsOneWidget);
    expect(transport.loads, 2);
  });

  for (final action in ['Revoke', 'New code for this device']) {
    for (final removeTile in [false, true]) {
      testWidgets(
        'confirmed $action survives resume${removeTile ? ' and tile removal' : ''}',
        (tester) async {
          final transport = _Transport();
          PairingPanelRequest? shown;
          await _pump(
            tester,
            transport,
            pairingPanel: (context, request) async {
              expect(context.mounted, isTrue);
              expect(Navigator.of(context), isNotNull);
              shown = request;
            },
          );
          await tester.tap(find.text(action));
          await tester.pumpAndSettle();
          final gate = Completer<void>();
          transport.loadingGate = gate;
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pump();
          await tester.pump();
          if (removeTile) {
            transport.hideDevice = true;
            gate.complete();
            await tester.pumpAndSettle();
            expect(find.text('Counter POS'), findsNothing);
          }
          await tester.tap(
            find.widgetWithText(
              FilledButton,
              action == 'Revoke' ? 'Revoke' : 'Issue code',
            ),
          );
          await tester.pump();
          if (!gate.isCompleted) gate.complete();
          await tester.pumpAndSettle();
          expect(
            action == 'Revoke' ? transport.revokedFor : transport.issuedFor,
            ['existing-device'],
          );
          if (action != 'Revoke') expect(shown?.code, 'test-code');
          if (action == 'Revoke') {
            final l10n = await AppLocalizations.delegate.load(
              const Locale('en'),
            );
            expect(find.text(l10n.adminDeviceUpdated), findsOneWidget);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('removed tile still presents its one-time replacement code', (
    tester,
  ) async {
    final transport = _Transport();
    await _pump(tester, transport);
    await tester.tap(find.text('New code for this device'));
    await tester.pumpAndSettle();
    transport.hideDevice = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Counter POS'), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Issue code'));
    await tester.pumpAndSettle();
    expect(transport.issuedFor, ['existing-device']);
    expect(find.text('test-code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'refresh keeps tile mounted without authoritative session labels',
    (tester) async {
      final transport = _Transport();
      await _pump(tester, transport);
      final tile = tester.element(
        find.byKey(const ValueKey('existing-device')),
      );
      final gate = Completer<void>();
      transport.loadingGate = gate;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump();
      expect(find.text('Counter POS'), findsOneWidget);
      expect(
        tester.element(find.byKey(const ValueKey('existing-device'))),
        same(tile),
      );
      expect(find.text('Session active'), findsNothing);
      expect(find.text('Session expired'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Session active'), findsOneWidget);
    },
  );

  testWidgets('unused code can be replaced before and after expiry', (
    tester,
  ) async {
    final transport = _Transport(status: 'none');
    await _pump(tester, transport, pairingPanel: (_, _) async {});
    await tester.tap(find.text('Issue code'));
    await tester.pumpAndSettle();
    expect(transport.issuedFor, ['existing-device']);
    expect(find.text('New code for this device'), findsOneWidget);
    transport.now = transport.codeExpiresAt!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    expect(find.text(l10n.adminDevStatusCodeExpired), findsOneWidget);
    await tester.tap(find.text('New code for this device'));
    await tester.pumpAndSettle();
    expect(transport.issuedFor, hasLength(1));
    await tester.tap(find.widgetWithText(FilledButton, 'Issue code'));
    await tester.pumpAndSettle();
    expect(transport.issuedFor, ['existing-device', 'existing-device']);
  });

  for (final delayed in [false, true]) {
    testWidgets(
      'cached active snapshot is refreshed on screen entry${delayed ? ' without displaying stale data' : ''}',
      (tester) async {
        final transport = _Transport();
        final container = ProviderContainer(
          overrides: adminFeatureOverrides(
            scope: AdminScope.demo,
            repository: SupabaseAdminDeviceRepository(
              transport: transport,
              scope: AdminScope.demo,
              currentUserId: () => 'manager',
            ),
          ),
        );
        final keepSnapshot = container.listen(adminDevicesProvider, (_, _) {});
        addTearDown(() {
          keepSnapshot.close();
          container.dispose();
        });
        await container.read(adminDevicesProvider.future);
        expect(transport.loads, 1);
        transport.expired = true;
        if (delayed) {
          final gate = Completer<void>();
          transport.loadingGate = gate;
          addTearDown(() {
            if (!gate.isCompleted) gate.complete();
          });
        }
        await _pump(
          tester,
          transport,
          cachedContainer: container,
          settle: !delayed,
        );
        expect(find.text('Session active'), findsNothing);
        if (delayed) {
          transport.loadingGate!.complete();
          await tester.pumpAndSettle();
        }
        expect(find.text('Session expired'), findsOneWidget);
        expect(transport.loads, 2);
      },
    );
  }

  testWidgets('app resume refreshes a session that expired while away', (
    tester,
  ) async {
    final transport = _Transport();
    await _pump(tester, transport);
    expect(find.text('Session active'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    transport.expired = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Session active'), findsNothing);
    expect(find.text('Session expired'), findsOneWidget);
    expect(transport.loads, 2);
  });

  for (final expired in [false, true]) {
    testWidgets(
      '${expired ? 'expired' : 'active'} session offers confirmed same-device code',
      (tester) async {
        final transport = _Transport(expired: expired);
        PairingPanelRequest? shown;
        await _pump(
          tester,
          transport,
          pairingPanel: (_, request) async {
            shown = request;
          },
        );
        expect(
          find.text(expired ? 'Session expired' : 'Session active'),
          findsOneWidget,
        );
        expect(
          find.text(expired ? 'Session active' : 'Session expired'),
          findsNothing,
        );
        expect(find.textContaining('Last activity:'), findsOneWidget);
        expect(find.text('Last activity: —'), findsNothing);

        await tester.tap(find.text('New code for this device'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('will end its previous sessions'),
          findsOneWidget,
        );
        expect(transport.issuedFor, isEmpty);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(transport.issuedFor, isEmpty);

        await tester.tap(find.text('New code for this device'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Issue code'));
        await tester.pumpAndSettle();
        expect(transport.issuedFor, ['existing-device']);
        expect(shown?.code, 'test-code');
        expect(shown?.deviceLabel, 'Counter POS');
        expect(transport.loads, 2);
      },
    );
  }

  testWidgets('expiry triggers a fresh server read while screen stays open', (
    tester,
  ) async {
    final transport = _Transport()..lifetime = const Duration(seconds: 2);
    await _pump(tester, transport);
    expect(find.text('Session active'), findsOneWidget);
    transport.expired = true;
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Session active'), findsNothing);
    expect(find.text('Session expired'), findsOneWidget);
    expect(transport.loads, 2);
  });

  testWidgets('renewal discovered at old expiry keeps the active display', (
    tester,
  ) async {
    final transport = _Transport()..lifetime = const Duration(seconds: 2);
    await _pump(tester, transport);
    transport.lifetime = const Duration(days: 30);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Session active'), findsOneWidget);
    expect(find.text('Session expired'), findsNothing);
    expect(transport.loads, 2);
  });

  testWidgets('old metadata does not claim active or expired', (tester) async {
    await _pump(tester, _Transport()..metadata = false);
    expect(find.text('Session active'), findsNothing);
    expect(find.text('Session expired'), findsNothing);
    expect(find.text('Last activity: —'), findsOneWidget);
  });

  testWidgets('explicit legacy NULL remains active', (tester) async {
    await _pump(tester, _Transport()..legacyNull = true);
    expect(find.text('Session active'), findsOneWidget);
    expect(find.text('Session expired'), findsNothing);
  });

  testWidgets('revoked history is never expired and offers no replacement', (
    tester,
  ) async {
    await _pump(tester, _Transport(expired: true, status: 'revoked'));
    await tester.tap(find.byKey(const Key('revoked-devices-section')));
    await tester.pumpAndSettle();
    expect(find.text('Counter POS'), findsOneWidget);
    expect(find.text('Session expired'), findsNothing);
    expect(find.text('New code for this device'), findsNothing);
  });

  testWidgets('never-paired device is not presented as expired', (
    tester,
  ) async {
    await _pump(tester, _Transport(expired: true, status: 'none'));
    expect(find.text('Session expired'), findsNothing);
    expect(find.text('Issue code'), findsOneWidget);
    expect(find.text('New code for this device'), findsNothing);
  });

  testWidgets('read-only role cannot issue replacement code', (tester) async {
    await _pump(
      tester,
      _Transport(expired: true),
      role: MembershipRole.cashier,
    );
    expect(find.text('New code for this device'), findsNothing);
    expect(find.text('Revoke'), findsNothing);
  });

  for (final language in ['en', 'ar', 'he']) {
    testWidgets('new session controls fit 390px at 2x in $language', (
      tester,
    ) async {
      final errors = <String>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('overflowed')) {
          errors.add(details.exceptionAsString());
        } else {
          previous?.call(details);
        }
      };
      try {
        await _pump(
          tester,
          _Transport(expired: true),
          locale: Locale(language),
          width: 390,
          scale: 2,
        );
      } finally {
        FlutterError.onError = previous;
      }
      expect(errors, isEmpty);
      final l10n = await AppLocalizations.delegate.load(Locale(language));
      expect(find.text(l10n.adminSessionExpired), findsOneWidget);
      expect(find.text(l10n.adminNewCodeForDevice), findsOneWidget);
    });
  }
}
