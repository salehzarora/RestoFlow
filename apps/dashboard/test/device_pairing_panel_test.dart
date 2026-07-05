import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:restoflow_dashboard/src/devices/device_pairing_panel.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart'
    show PairingPanelRequest;
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// LIVE-OPS-001 — the Dashboard QR pairing panel: QR + copyable origin-derived
/// link + manual code, with the link routed by device type; unknown types show
/// the manual code only (no QR/link). Origin is injected for determinism.
Future<void> _pump(
  WidgetTester tester,
  PairingPanelRequest request, {
  Uri? base,
  Locale locale = const Locale('en'),
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(
        body: DevicePairingPanel(request: request, base: base),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _selectable(WidgetTester tester, Key rowKey) => tester
    .widget<SelectableText>(
      find.descendant(
        of: find.byKey(rowKey),
        matching: find.byType(SelectableText),
      ),
    )
    .data!;

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  testWidgets('POS: QR + link -> {origin}/pos?pair=CODE + the manual code', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(
      tester,
      const PairingPanelRequest(
        deviceLabel: 'Counter POS',
        deviceType: 'pos',
        code: 'ABC123',
      ),
      base: Uri.parse('https://app.example/settings?tab=devices'),
    );

    expect(find.text(l10n.pairingPanelTitle), findsOneWidget);
    expect(find.text('Counter POS'), findsOneWidget);
    // A locally-rendered QR is present.
    expect(find.byKey(const Key('pairing-qr')), findsOneWidget);
    expect(find.byType(QrImageView), findsOneWidget);
    // The link is origin-derived, routed to /pos, and copyable.
    expect(
      _selectable(tester, const Key('pairing-link')),
      'https://app.example/pos?pair=ABC123',
    );
    expect(find.text(l10n.pairingPanelLinkLabel), findsOneWidget);
    expect(find.text(l10n.pairingPanelCopyLink), findsNothing); // tooltip only
    // The manual code is still shown as a fallback.
    expect(_selectable(tester, const Key('pairing-code')), 'ABC123');
    // Copy affordances exist for both link and code.
    expect(find.byIcon(Icons.copy_outlined), findsNWidgets(2));
  });

  testWidgets('KDS: link routes to /kds', (tester) async {
    await _pump(
      tester,
      const PairingPanelRequest(
        deviceLabel: 'Kitchen display',
        deviceType: 'kds',
        code: 'K-9',
      ),
      base: Uri.parse('https://resto.example/'),
    );
    expect(find.byKey(const Key('pairing-qr')), findsOneWidget);
    expect(
      _selectable(tester, const Key('pairing-link')),
      'https://resto.example/kds?pair=K-9',
    );
  });

  testWidgets('preserves a localhost origin WITH port', (tester) async {
    await _pump(
      tester,
      const PairingPanelRequest(
        deviceLabel: 'Dev POS',
        deviceType: 'pos',
        code: 'DEV1',
      ),
      base: Uri.parse('http://localhost:5541/#/x'),
    );
    expect(
      _selectable(tester, const Key('pairing-link')),
      'http://localhost:5541/pos?pair=DEV1',
    );
  });

  testWidgets('unknown device type: manual code ONLY, no QR / link', (
    tester,
  ) async {
    final l10n = await _en();
    await _pump(
      tester,
      const PairingPanelRequest(
        deviceLabel: 'Label printer',
        deviceType: 'printer',
        code: 'P-1',
      ),
      base: Uri.parse('https://app.example/'),
    );
    // No QR and no link row for an unknown type.
    expect(find.byKey(const Key('pairing-qr')), findsNothing);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.byKey(const Key('pairing-link')), findsNothing);
    // A clear "enter it manually" note + the code itself.
    expect(find.text(l10n.pairingPanelManualOnly), findsOneWidget);
    expect(_selectable(tester, const Key('pairing-code')), 'P-1');
  });

  testWidgets('renders RTL in Arabic without error', (tester) async {
    await _pump(
      tester,
      const PairingPanelRequest(
        deviceLabel: 'شاشة المطبخ',
        deviceType: 'kds',
        code: 'AR-1',
      ),
      base: Uri.parse('https://app.example/'),
      locale: const Locale('ar'),
    );
    expect(tester.takeException(), isNull);
    expect(
      Directionality.of(tester.element(find.byType(DevicePairingPanel))),
      TextDirection.rtl,
    );
  });
}
