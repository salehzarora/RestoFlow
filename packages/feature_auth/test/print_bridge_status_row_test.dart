import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// RF-115: the shared device-settings bridge row renders the HONEST bridge
/// state (connected / unavailable + last job) and is HIDDEN when no bridge is
/// configured — reaching both POS and KDS device settings from one widget.

AsyncValue<Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>?>
_assignments() => AsyncValue.data(
  Success(
    DevicePrinterAssignments(
      fetchedAt: DateTime(2026, 7, 4, 9, 30),
      printers: const [],
    ),
  ),
);

Future<void> _pump(
  WidgetTester tester, {
  required PrinterBridgeStatus? bridgeStatus,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: restoflowLocalizationsDelegates,
      supportedLocales: kSupportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => SingleChildScrollView(
            child: PrinterAssignmentsSection(
              l10n: AppLocalizations.of(context),
              assignmentsAsync: _assignments(),
              bridgeStatus: bridgeStatus,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no bridge configured -> the row is hidden', (tester) async {
    await _pump(tester, bridgeStatus: null);
    expect(find.byKey(const Key('bridge-status-row')), findsNothing);
  });

  testWidgets('connected -> shows connected + last job time', (tester) async {
    await _pump(
      tester,
      bridgeStatus: PrinterBridgeStatus(
        connectivity: PrintBridgeConnectivity.connected,
        lastJobAt: DateTime(2026, 7, 4, 14, 5),
      ),
    );
    expect(find.byKey(const Key('bridge-status-row')), findsOneWidget);
    expect(find.textContaining('connected'), findsOneWidget);
    expect(find.textContaining('14:05'), findsOneWidget);
  });

  testWidgets('unavailable -> shows unavailable', (tester) async {
    await _pump(
      tester,
      bridgeStatus: const PrinterBridgeStatus(
        connectivity: PrintBridgeConnectivity.unavailable,
      ),
    );
    expect(find.byKey(const Key('bridge-status-row')), findsOneWidget);
    expect(find.textContaining('unavailable'), findsOneWidget);
  });
}
