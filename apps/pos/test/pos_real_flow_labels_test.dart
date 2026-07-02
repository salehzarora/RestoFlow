import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_data_remote/restoflow_data_remote.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/demo_menu.dart';
import 'package:restoflow_pos/src/data/outbox_repository.dart';
import 'package:restoflow_pos/src/pos_menu_screen.dart';
import 'package:restoflow_pos/src/state/outbox_controller.dart';
import 'package:restoflow_pos/src/state/pos_menu_provider.dart';
import 'package:restoflow_pos/src/state/pos_session.dart';

/// Demo-readiness sprint (Part B): after a REAL paired-device + staff-PIN
/// session, the POS order flow is REAL — no demo shift label, no demo order
/// notice, no "Sync now (demo)", no DEMO-nnnn number; submit pushes
/// automatically and a backend reject shows an honest error with Retry.

const SyncSession _session = SyncSession(
  pinSessionId: 'pin-1',
  deviceId: 'dev-1',
);

class _ScriptedTransport implements SyncRpcTransport {
  _ScriptedTransport({required this.applied});
  final bool applied;
  int pushes = 0;

  @override
  Future<Object?> invoke(String function, Map<String, dynamic> p) async {
    pushes++;
    final op = (p['p_operations'] as List).first as Map<String, dynamic>;
    return <String, dynamic>{
      'ok': true,
      'results': <dynamic>[
        <String, dynamic>{
          'local_operation_id': op['local_operation_id'],
          'operation_type': 'order.submit',
          'ok': applied,
          'status': applied ? 'applied' : 'rejected',
          if (!applied) 'error': 'invalid_payload',
        },
      ],
      'server_ts': '2026-07-03T09:00:01Z',
    };
  }
}

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

Future<_ScriptedTransport> _pumpReal(
  WidgetTester tester, {
  required bool applied,
}) async {
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final transport = _ScriptedTransport(applied: applied);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posSyncSessionProvider.overrideWithValue(_session),
        outboxRepositoryProvider.overrideWithValue(
          RealOutboxRepository(transport, _session),
        ),
        // The REAL post-PIN surface with a known menu (the pos_menu RPC has
        // its own unit suites; this test is about the ORDER flow labels).
        posMenuProvider.overrideWith(
          (ref) async => const PosMenuData(
            categories: kDemoCategories,
            items: kDemoMenu,
            currencyCode: 'ILS',
          ),
        ),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const PosMenuScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return transport;
}

Future<void> _addItemAndSend(WidgetTester tester, AppLocalizations l10n) async {
  await tester.tap(find.byIcon(Icons.add_shopping_cart).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.posSendOrder));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('REAL submit auto-sends: no demo labels, no Sync now (demo), '
      'no DEMO number — the backend state is shown', (tester) async {
    final l10n = await _en();
    final transport = await _pumpReal(tester, applied: true);

    // The REAL shift bar (auto-opened server shift), never the demo shift.
    expect(find.text(l10n.posShiftRealName), findsOneWidget);
    expect(find.text(l10n.posShiftDemoName), findsNothing);
    expect(find.text(l10n.posShiftDemoNote), findsNothing);

    await _addItemAndSend(tester, l10n);

    // Pushed automatically at submit — exactly one push, no button tap.
    expect(transport.pushes, 1);
    expect(find.text(l10n.posOrderSubmittedTitle), findsOneWidget);
    expect(find.text(l10n.posSyncStateSynced), findsOneWidget);
    expect(find.text(l10n.posSyncSentReal), findsOneWidget);
    // Never any demo wording or the demo sync button in real mode.
    expect(find.text(l10n.posDemoOrderNotice), findsNothing);
    expect(find.text(l10n.posSyncDemoNotice), findsNothing);
    expect(find.text(l10n.posSyncNow), findsNothing);
    expect(find.byKey(const Key('sync-now-button')), findsNothing);
    expect(find.textContaining('DEMO-'), findsNothing);
    // The order number is the shared display code (#XXXXXX).
    final numberText = tester.widget<Text>(
      find.byKey(const Key('order-number')),
    );
    expect(numberText.data, matches(RegExp(r'^#[0-9A-F]{6}$')));
  });

  testWidgets('a backend REJECT is an honest failure with Retry — never a '
      'pretended send', (tester) async {
    final l10n = await _en();
    await _pumpReal(tester, applied: false);
    await _addItemAndSend(tester, l10n);

    expect(find.text(l10n.posSyncStateFailed), findsOneWidget);
    expect(find.text(l10n.posSyncFailedReal), findsOneWidget);
    expect(find.byKey(const Key('sync-retry-button')), findsOneWidget);
    expect(find.text(l10n.posSyncSentReal), findsNothing);
    expect(find.text(l10n.posSyncDemoNotice), findsNothing);
  });
}
