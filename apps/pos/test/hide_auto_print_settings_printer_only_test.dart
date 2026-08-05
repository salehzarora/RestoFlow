import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/kitchen_mode_readiness.dart'
    show posVerifiedKitchenModeProvider;
import 'package:restoflow_pos/src/state/pos_auto_print_prefs.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_printer_assignments.dart';
import 'package:restoflow_pos/src/widgets/device_settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// HIDE-REDUNDANT-AUTO-PRINT-SETTINGS-014.
///
/// On a `printer_only` branch the POS *is* the kitchen: the ticket and the
/// receipt print from this station by definition. Asking the cashier to opt in
/// is redundant, and a stale stored `false` would silently stop the kitchen
/// seeing food. So both switches are hidden and both effective behaviours are
/// forced ON — WITHOUT touching the stored preference, which takes over again
/// the moment the branch returns to `kds`.
///
/// One shared resolver (`posPrinterOnlyAutoPrintProvider`) drives both the UI
/// visibility and the runtime print decisions, so they cannot disagree.

/// `KitchenModeResult` carries a real DateTime; a fixed one keeps the fixtures
/// deterministic without pulling a clock into the test.
final DateTime _verifiedAt = DateTime.utc(2026, 8, 1, 9);

final _printerOnly = KitchenModePrinterOnlyWithRevision(
  revision: 4,
  verifiedAt: _verifiedAt,
);
final _kds = KitchenModeVerifiedKds(verifiedAt: _verifiedAt, revision: 4);

class _FakeAssignmentsReader implements DevicePrinterAssignmentsReader {
  _FakeAssignmentsReader(this.assignments);
  final DevicePrinterAssignments assignments;

  @override
  Future<Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>>
  load() async => Success(assignments);
}

DevicePrinterAssignments _assignments() => DevicePrinterAssignments(
  fetchedAt: DateTime(2026, 8, 1, 12, 30),
  deviceLabel: 'Front POS',
  deviceType: 'pos',
  restaurantName: 'Maps Burger',
  branchName: 'Kafr Manda',
  printers: const [
    AssignedPrinter(
      id: 'prn-1',
      displayName: 'Counter receipt',
      role: 'receipt',
      connectionType: 'network',
      paperWidth: '80mm',
      isEnabled: true,
    ),
  ],
);

class _SeededPosContext extends PosDeviceContextController {
  @override
  DeviceContext? build() => const DeviceContext(
    organizationId: 'org-1',
    restaurantId: 'rest-1',
    branchId: 'branch-1',
    deviceId: 'dev-1',
  );
}

Future<AppLocalizations> _en() =>
    AppLocalizations.delegate.load(const Locale('en'));

const _receiptKey = Key('auto-print-receipt-toggle');
const _kitchenKey = Key('auto-print-kitchen-ticket-toggle');

Future<void> _pumpSheet(
  WidgetTester tester, {
  required KitchenModeResult? mode,
}) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        runtimeConfigProvider.overrideWithValue(
          RuntimeConfig.test(isDemoMode: false),
        ),
        posDeviceContextProvider.overrideWith(_SeededPosContext.new),
        posPrinterAssignmentsReaderProvider.overrideWithValue(
          _FakeAssignmentsReader(_assignments()),
        ),
        posVerifiedKitchenModeProvider.overrideWithValue(mode),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        home: const Scaffold(body: PosDeviceSettingsSheet()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The shared resolver, read through a real container.
bool _forced(KitchenModeResult? mode) {
  final c = ProviderContainer(
    overrides: [posVerifiedKitchenModeProvider.overrideWithValue(mode)],
  );
  addTearDown(c.dispose);
  return c.read(posPrinterOnlyAutoPrintProvider);
}

void main() {
  group('1+2. device settings UI', () {
    testWidgets('printer_only hides BOTH controls and the whole section — no '
        'switch, no label, no helper text, no empty heading', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final l10n = await _en();
      await _pumpSheet(tester, mode: _printerOnly);

      expect(find.byKey(_receiptKey), findsNothing);
      expect(find.byKey(_kitchenKey), findsNothing);
      expect(find.text(l10n.deviceSettingsAutoPrintHeading), findsNothing);
      expect(find.text(l10n.posAutoPrintReceiptToggle), findsNothing);
      expect(find.text(l10n.posAutoPrintKitchenTicketToggle), findsNothing);
      expect(
        find.text(l10n.posAutoPrintKitchenTicketToggleExplanation),
        findsNothing,
      );
      expect(find.text(l10n.autoPrintReceiptNoPrinterNote), findsNothing);
      expect(find.text(l10n.autoPrintKitchenNoPrinterNote), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('kds keeps the RECEIPT control; the kitchen control is gone', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final l10n = await _en();
      await _pumpSheet(tester, mode: _kds);

      expect(find.byKey(_receiptKey), findsOneWidget);
      expect(find.text(l10n.deviceSettingsAutoPrintHeading), findsOneWidget);
      // Editable, with the shipped default: receipt ON.
      expect(
        tester.widget<SwitchListTile>(find.byKey(_receiptKey)).onChanged,
        isNotNull,
      );
      expect(
        tester.widget<SwitchListTile>(find.byKey(_receiptKey)).value,
        isTrue,
      );
      // POS-KITCHEN-WORKFLOW-REGRESSION-001: 014 hid the kitchen switch only for
      // a resolved printer_only branch, so a Separate-KDS branch still offered
      // it. On a KDS branch the KDS owns the ticket, so a local switch could
      // only ever contradict the Dashboard — it is now absent here too.
      expect(find.byKey(_kitchenKey), findsNothing);
    });

    testWidgets('8. unrelated printer settings are untouched in printer_only', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final l10n = await _en();
      await _pumpSheet(tester, mode: _printerOnly);

      // The assigned-printer section, its metadata and the honest status all
      // remain; only the two redundant switches went.
      expect(find.byKey(const Key('printer-prn-1')), findsOneWidget);
      expect(find.text('Counter receipt'), findsOneWidget);
      expect(find.text(l10n.deviceSettingsBridgeRequired), findsOneWidget);
      expect(find.text('Maps Burger'), findsOneWidget);
      expect(find.text('Kafr Manda'), findsOneWidget);
    });
  });

  group('3+4+5. effective behaviour and stored-value preservation', () {
    test('printer_only forces BOTH effective values on even when the stored '
        'preferences are explicitly false', () {
      expect(
        posAutoPrintReceiptEnabled(
          stored: false,
          hasEnabledPrinter: true,
          printerOnly: true,
        ),
        isTrue,
      );
      expect(
        posAutoPrintKitchenTicketEnabled(
          stored: false,
          hasKitchenPrinter: true,
          printerOnly: true,
        ),
        isTrue,
      );
    });

    test('kds resolves from the STORED preferences (receipt default on, '
        'kitchen default off) — unchanged behaviour', () {
      expect(
        posAutoPrintReceiptEnabled(stored: false, hasEnabledPrinter: true),
        isFalse,
      );
      expect(
        posAutoPrintReceiptEnabled(stored: null, hasEnabledPrinter: true),
        isTrue,
      );
      expect(
        posAutoPrintKitchenTicketEnabled(
          stored: false,
          hasKitchenPrinter: true,
        ),
        isFalse,
      );
      expect(
        posAutoPrintKitchenTicketEnabled(stored: null, hasKitchenPrinter: true),
        isFalse,
      );
    });

    test('the printer precondition still governs: no printer means no '
        'automatic print, even in printer_only', () {
      expect(
        posAutoPrintReceiptEnabled(
          stored: true,
          hasEnabledPrinter: false,
          printerOnly: true,
        ),
        isFalse,
      );
      expect(
        posAutoPrintKitchenTicketEnabled(
          stored: true,
          hasKitchenPrinter: false,
          printerOnly: true,
        ),
        isFalse,
      );
    });

    testWidgets('the STORED preferences are never overwritten: false survives '
        'a printer_only session and governs again under kds', (tester) async {
      const rk = 'restoflow.autoprint.pos.receiptOnPaid.dev-1';
      const kk = 'restoflow.autoprint.pos.kitchenTicket.dev-1';
      SharedPreferences.setMockInitialValues({rk: false, kk: false});

      // A full printer_only session: the controls are gone and both effective
      // values are forced true.
      await _pumpSheet(tester, mode: _printerOnly);
      expect(find.byKey(_receiptKey), findsNothing);
      expect(_forced(_printerOnly), isTrue);

      // NOTHING was written: the cashier's stored `false` is still there.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(rk), isFalse);
      expect(prefs.getBool(kk), isFalse);

      // Back on kds the stored RECEIPT value governs again and its switch
      // returns. The kitchen switch does NOT return — POS-KITCHEN-WORKFLOW-
      // REGRESSION-001 made the Dashboard workflow the sole authority there.
      await _pumpSheet(tester, mode: _kds);
      expect(find.byKey(_receiptKey), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byKey(_receiptKey)).value,
        isFalse,
      );
      expect(find.byKey(_kitchenKey), findsNothing);

      // The non-destructive guarantee is unchanged and is the point of this
      // test: the stored kitchen value is still on disk, byte-for-byte. It is
      // ignored where the central workflow applies, never deleted.
      expect(prefs.getBool(rk), isFalse);
      expect(prefs.getBool(kk), isFalse);
    });
  });

  group('6+7. loading and failure fail SAFE (never assume printer_only)', () {
    test('an unresolved mode does NOT force automatic printing', () {
      expect(_forced(null), isFalse);
      expect(
        posAutoPrintReceiptEnabled(
          stored: false,
          hasEnabledPrinter: true,
          printerOnly: _forced(null),
        ),
        isFalse,
        reason: 'the stored preference still decides while the mode is unknown',
      );
    });

    test('every non-printer_only verdict — including the typed failures — '
        'leaves the stored preferences in charge', () {
      for (final m in <KitchenModeResult>[
        _kds,
        const KitchenModeRevisionUnavailable(),
        const KitchenModeInvalidSession(),
        const KitchenModeTransientFailure(),
      ]) {
        expect(_forced(m), isFalse, reason: m.runtimeType.toString());
      }
    });

    testWidgets('while the mode is unresolved the two switches are NOT hidden '
        'and no preference is mutated', (tester) async {
      const rk = 'restoflow.autoprint.pos.receiptOnPaid.dev-1';
      SharedPreferences.setMockInitialValues({rk: false});
      await _pumpSheet(tester, mode: null);

      // The existing kds-shaped behaviour is what a still-loading device shows;
      // it is never replaced by a printer_only assumption.
      expect(find.byKey(_receiptKey), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byKey(_receiptKey)).value,
        isFalse,
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(rk), isFalse, reason: 'nothing was written');
    });
  });
}
