import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_design_system/restoflow_design_system.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

class _FakePairing implements DevicePairingRepository {
  _FakePairing(this.result);
  Result<DeviceContext, PairingFailure> result;
  String? lastCode;
  String? lastType;

  @override
  Future<Result<DeviceContext, PairingFailure>> pairWithCode({
    required String code,
    required String deviceType,
  }) async {
    lastCode = code;
    lastType = deviceType;
    return result;
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget home, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      theme: restoflowBaseTheme(),
      home: home,
    ),
  );
  await tester.pumpAndSettle();
}

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  testWidgets('validates an empty pairing code (never calls the repository)', (
    tester,
  ) async {
    final l10n = await _en();
    final repo = _FakePairing(
      const Failure(PairingFailure(PairingFailureKind.invalidCode)),
    );
    await _pump(
      tester,
      DevicePairingScreen(
        repository: repo,
        deviceType: 'pos',
        onPaired: (_) {},
      ),
    );
    await tester.tap(find.byKey(const Key('pairing-submit')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.pairingCodeRequired), findsOneWidget);
    expect(repo.lastCode, isNull);
  });

  testWidgets('a successful pair hands the backend context to onPaired', (
    tester,
  ) async {
    DeviceContext? paired;
    final repo = _FakePairing(
      const Success(
        DeviceContext(
          organizationId: 'o',
          branchId: 'b',
          deviceId: 'd',
          deviceType: 'pos',
          stationId: 's',
        ),
      ),
    );
    // The harness transitions away on success (like a real parent gate).
    await _pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => paired == null
            ? DevicePairingScreen(
                repository: repo,
                deviceType: 'pos',
                onPaired: (c) => setState(() => paired = c),
              )
            : const Text('paired', textDirection: TextDirection.ltr),
      ),
    );
    await tester.enterText(find.byKey(const Key('pairing-code')), 'CODE-123');
    await tester.tap(find.byKey(const Key('pairing-submit')));
    await tester.pumpAndSettle();

    expect(repo.lastCode, 'CODE-123');
    expect(repo.lastType, 'pos');
    expect(paired?.isPaired, isTrue);
    expect(paired?.deviceId, 'd');
    expect(find.text('paired'), findsOneWidget);
  });

  testWidgets(
    'an invalid code shows a SAFE localized error (no device faked)',
    (tester) async {
      final l10n = await _en();
      DeviceContext? paired;
      final repo = _FakePairing(
        const Failure(PairingFailure(PairingFailureKind.invalidCode)),
      );
      await _pump(
        tester,
        DevicePairingScreen(
          repository: repo,
          deviceType: 'kds',
          onPaired: (c) => paired = c,
        ),
      );
      await tester.enterText(find.byKey(const Key('pairing-code')), 'nope');
      await tester.tap(find.byKey(const Key('pairing-submit')));
      await tester.pumpAndSettle();

      expect(find.text(l10n.pairingInvalidCode), findsOneWidget);
      expect(paired, isNull);
    },
  );

  testWidgets('renders RTL in Arabic without error', (tester) async {
    final repo = _FakePairing(
      const Failure(PairingFailure(PairingFailureKind.unknown)),
    );
    await _pump(
      tester,
      DevicePairingScreen(
        repository: repo,
        deviceType: 'pos',
        onPaired: (_) {},
      ),
      locale: const Locale('ar'),
    );
    expect(tester.takeException(), isNull);
    expect(
      Directionality.of(tester.element(find.byType(DevicePairingScreen))),
      TextDirection.rtl,
    );
  });
}
