import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_kiosk/src/screens/kiosk_activation.dart';

/// KIOSK-001-DEVICE-088 — `/kiosk?pair=CODE` PREFILL contract: the Dashboard
/// link/QR prefills the enrollment code, but the operator still confirms —
/// the screen NEVER auto-redeems, the field stays editable, and a blank
/// prefill leaves the field empty.
class _RecordingPairing implements DevicePairingRepository {
  final List<(String, String)> calls = [];

  @override
  Future<Result<DeviceContext, PairingFailure>> pairWithCode({
    required String code,
    required String deviceType,
  }) async {
    calls.add((code, deviceType));
    return const Failure(PairingFailure(PairingFailureKind.network));
  }
}

Future<void> _pump(
  WidgetTester tester,
  _RecordingPairing pairing, {
  String? initialCode,
}) async {
  tester.view.physicalSize = const Size(1080, 1920);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: KioskActivationScreen(
        pairing: pairing,
        onPaired: (_) {},
        initialCode: initialCode,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('a pair-link code PREFILLS the field but never auto-redeems', (
    tester,
  ) async {
    final pairing = _RecordingPairing();
    await _pump(tester, pairing, initialCode: 'ABC123');
    final field = tester.widget<TextField>(
      find.byKey(const Key('kiosk-activation-code')),
    );
    expect(field.controller!.text, 'ABC123');
    // NO redeem happened from the prefill alone — operator action required.
    await tester.pump(const Duration(seconds: 1));
    expect(pairing.calls, isEmpty);
  });

  testWidgets('the prefilled code stays EDITABLE and submits what is typed', (
    tester,
  ) async {
    final pairing = _RecordingPairing();
    await _pump(tester, pairing, initialCode: 'ABC123');
    await tester.enterText(
      find.byKey(const Key('kiosk-activation-code')),
      'EDITED-9',
    );
    await tester.tap(find.byKey(const Key('kiosk-activation-submit')));
    await tester.pump();
    expect(pairing.calls.single, ('EDITED-9', 'kiosk'));
  });

  testWidgets('no pair parameter -> empty field, still no redeem', (
    tester,
  ) async {
    final pairing = _RecordingPairing();
    await _pump(tester, pairing);
    final field = tester.widget<TextField>(
      find.byKey(const Key('kiosk-activation-code')),
    );
    expect(field.controller!.text, isEmpty);
    // Submitting an EMPTY field is a no-op (no wasted redeem attempt).
    await tester.tap(find.byKey(const Key('kiosk-activation-submit')));
    await tester.pump();
    expect(pairing.calls, isEmpty);
  });
}
