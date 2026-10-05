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

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> params) async {
    if (function == 'list_devices') {
      loads++;
      await loadingGate?.future;
      return {
        'ok': true,
        if (metadata) 'server_now': now.toIso8601String(),
        'devices': [
          {
            'device_id': 'existing-device',
            'label': 'Counter POS',
            'device_type': 'pos',
            'branch_label': 'Main',
            'status': status,
            'device_pairing_id': status == 'none' ? null : 'pairing',
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
      status = 'code_issued';
      return {
        'ok': true,
        'device_id': params['p_device_id'],
        'device_pairing_id': 'replacement-pairing',
        'enrollment_code': 'test-code',
      };
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
    home: const Scaffold(body: AdminDevicesScreen()),
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
