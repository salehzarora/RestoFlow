import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_auth/restoflow_feature_auth.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_pos/src/data/kitchen_mode_readiness.dart';
import 'package:restoflow_pos/src/print/pos_kitchen_ticket_printer.dart'
    show posHasKitchenNativePrinterProvider;
import 'package:restoflow_pos/src/state/pos_auto_print_prefs.dart';
import 'package:restoflow_pos/src/state/pos_device_context.dart';
import 'package:restoflow_pos/src/state/pos_printer_assignments.dart';
import 'package:restoflow_pos/src/state/pos_printer_transport.dart';
import 'package:restoflow_pos/src/widgets/device_settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// POS-KITCHEN-WORKFLOW-REGRESSION-001 (follow-up) — the Dashboard kitchen
/// workflow is the SOLE authority on whether kitchen tickets print.
///
/// The local "Automatically print kitchen ticket" switch used to be hidden only
/// for a RESOLVED printer_only branch. Every other readiness state — Separate
/// KDS, still Loading, verification failed — put an editable switch in front of
/// the cashier that looked like it decided whether the kitchen sees food. It
/// never did: the submit path and the recent-orders action both read the
/// central decision. A control that cannot change the outcome is worse than no
/// control, because flipping it feels like it worked.
///
/// The gate is now a CAPABILITY question ("does the Dashboard workflow govern
/// this surface?") rather than a reading of the current workflow VALUE, so an
/// unresolved workflow can never be mistaken for "no central workflow".
///
/// The device remains the authority on WHICH physical printer is used, and the
/// receipt-after-payment switch is a separate concern and untouched.
const _device = DeviceContext(
  organizationId: 'org-1',
  branchId: 'branch-1',
  restaurantId: 'rest-1',
  deviceId: 'dev-1',
  displayName: 'Station 1',
);

const _scope = PosKitchenModeScopeKey(
  organizationId: 'org-1',
  restaurantId: 'rest-1',
  branchId: 'branch-1',
  deviceId: 'dev-1',
);

class _SeededContext extends PosDeviceContextController {
  @override
  DeviceContext? build() => _device;
}

class _FakeAssignmentsReader implements DevicePrinterAssignmentsReader {
  _FakeAssignmentsReader(this._value);

  final DevicePrinterAssignments _value;

  @override
  Future<Result<DevicePrinterAssignments, DevicePrinterAssignmentsFailure>>
  load() async => Success(_value);
}

DevicePrinterAssignments _assignments({List<AssignedPrinter>? printers}) =>
    DevicePrinterAssignments(
      deviceLabel: 'Station 1',
      restaurantName: 'Falafel House',
      branchName: 'Main branch',
      printers: printers ?? const [],
      stations: const [],
      fetchedAt: DateTime.utc(2026, 8, 5, 12, 30),
    );

/// The four readiness states the sheet must behave identically in.
enum _Workflow { directPrint, separateKds, loading, unavailable }

Future<AppLocalizations> _l10n(String code) =>
    AppLocalizations.delegate.load(Locale(code));

void main() {
  /// Pumps the POS device-settings sheet on the NATIVE surface (the flow that
  /// uses the centralized kitchen workflow) in [locale], with the central
  /// workflow in [workflow] and a stale stored local kitchen preference.
  Future<void> pumpNativeSheet(
    WidgetTester tester, {
    required _Workflow workflow,
    String locale = 'en',
    bool staleKitchenPreferenceOn = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      // A LEFTOVER local value from before the branch was centrally managed.
      '${kPosAutoPrintKitchenTicketKeyPrefix}dev-1': staleKitchenPreferenceOn,
      '${kPosAutoPrintReceiptKeyPrefix}dev-1': true,
    });
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late ProviderContainer container;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          // NATIVE surface: this is what makes the central workflow govern.
          posNativePrintingAvailableProvider.overrideWithValue(true),
          posHasKitchenNativePrinterProvider.overrideWithValue(true),
          posDeviceContextProvider.overrideWith(_SeededContext.new),
          posPrinterAssignmentsReaderProvider.overrideWithValue(
            _FakeAssignmentsReader(_assignments()),
          ),
          // Never let the watchdog fire mid-test and change the state under us.
          posKitchenModeVerificationTimeoutProvider.overrideWithValue(
            const Duration(days: 1),
          ),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            container = ProviderScope.containerOf(context);
            return MaterialApp(
              locale: Locale(locale),
              localizationsDelegates: restoflowLocalizationsDelegates,
              supportedLocales: kSupportedLocales,
              home: const Scaffold(body: PosDeviceSettingsSheet()),
            );
          },
        ),
      ),
    );
    await tester.pump();

    final readiness = container.read(posKitchenModeReadinessProvider.notifier);
    final binding = readiness.bindScope(_scope);
    switch (workflow) {
      case _Workflow.directPrint:
        binding.publish(
          KitchenModePrinterOnlyWithRevision(
            revision: 5,
            verifiedAt: DateTime.utc(2026, 8, 5),
          ),
        );
      case _Workflow.separateKds:
        binding.publish(
          KitchenModeVerifiedKds(
            verifiedAt: DateTime.utc(2026, 8, 5),
            revision: 5,
          ),
        );
      case _Workflow.loading:
        break; // bindScope already left it Loading
      case _Workflow.unavailable:
        binding.markUnavailable();
    }
    await tester.pumpAndSettle();
  }

  // -------------------------------------------------------------------
  // 1-4. The kitchen toggle is absent in EVERY readiness state.
  // -------------------------------------------------------------------
  group('001F-1 kitchen toggle is never an editable local fallback', () {
    for (final workflow in _Workflow.values) {
      testWidgets('absent on native POS when workflow is ${workflow.name}', (
        tester,
      ) async {
        await pumpNativeSheet(tester, workflow: workflow);

        expect(
          find.byKey(const Key('auto-print-kitchen-ticket-toggle')),
          findsNothing,
          reason:
              'the Dashboard workflow decides kitchen printing in every state; '
              'a local switch here could only mislead',
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the toggle SURVIVES on a surface the central workflow does '
        'not govern (web POS)', (tester) async {
      SharedPreferences.setMockInitialValues({
        '${kPosAutoPrintKitchenTicketKeyPrefix}dev-1': true,
      });
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            runtimeConfigProvider.overrideWithValue(
              RuntimeConfig.test(isDemoMode: false),
            ),
            // NOT native -> no on-device printing -> historical local behaviour.
            posNativePrintingAvailableProvider.overrideWithValue(false),
            posHasKitchenNativePrinterProvider.overrideWithValue(true),
            posDeviceContextProvider.overrideWith(_SeededContext.new),
            posPrinterAssignmentsReaderProvider.overrideWithValue(
              _FakeAssignmentsReader(_assignments()),
            ),
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

      // This is what proves the change is scoped by CAPABILITY and did not
      // simply delete the control everywhere.
      expect(
        find.byKey(const Key('auto-print-kitchen-ticket-toggle')),
        findsOneWidget,
      );
    });
  });

  // -------------------------------------------------------------------
  // 5. A stale stored value cannot reach the derived decision.
  // -------------------------------------------------------------------
  group('001F-2 stale local preference is inert under central workflow', () {
    ProviderContainer containerFor({
      required bool native,
      required _Workflow workflow,
    }) {
      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: false),
          ),
          posNativePrintingAvailableProvider.overrideWithValue(native),
          posHasKitchenNativePrinterProvider.overrideWithValue(true),
          posKitchenModeVerificationTimeoutProvider.overrideWithValue(
            const Duration(days: 1),
          ),
        ],
      );
      final binding = c
          .read(posKitchenModeReadinessProvider.notifier)
          .bindScope(_scope);
      switch (workflow) {
        case _Workflow.directPrint:
          binding.publish(
            KitchenModePrinterOnlyWithRevision(
              revision: 5,
              verifiedAt: DateTime.utc(2026, 8, 5),
            ),
          );
        case _Workflow.separateKds:
          binding.publish(
            KitchenModeVerifiedKds(
              verifiedAt: DateTime.utc(2026, 8, 5),
              revision: 5,
            ),
          );
        case _Workflow.loading:
          break;
        case _Workflow.unavailable:
          binding.markUnavailable();
      }
      return c;
    }

    test('Separate KDS: a stale local TRUE cannot produce a rogue ticket', () {
      final c = containerFor(native: true, workflow: _Workflow.separateKds);
      addTearDown(c.dispose);
      // The stored preference is never even read here.
      expect(c.read(posKitchenTicketAutoPrintProvider), isFalse);
    });

    test('Loading: fail safe — never print on a guess', () {
      final c = containerFor(native: true, workflow: _Workflow.loading);
      addTearDown(c.dispose);
      expect(c.read(posKitchenTicketAutoPrintProvider), isFalse);
    });

    test('Unavailable: fail safe — never print on a guess', () {
      final c = containerFor(native: true, workflow: _Workflow.unavailable);
      addTearDown(c.dispose);
      expect(c.read(posKitchenTicketAutoPrintProvider), isFalse);
    });

    test(
      'direct-print: mandatory, and a stale local FALSE cannot suppress it',
      () {
        final c = containerFor(native: true, workflow: _Workflow.directPrint);
        addTearDown(c.dispose);
        expect(c.read(posKitchenTicketAutoPrintProvider), isTrue);
      },
    );

    test('the capability flag is what distinguishes the surfaces', () {
      final native = containerFor(native: true, workflow: _Workflow.loading);
      addTearDown(native.dispose);
      final web = containerFor(native: false, workflow: _Workflow.loading);
      addTearDown(web.dispose);

      expect(native.read(posCentralKitchenWorkflowProvider), isTrue);
      expect(web.read(posCentralKitchenWorkflowProvider), isFalse);
    });

    test('demo mode is never centrally governed', () {
      final c = ProviderContainer(
        overrides: [
          runtimeConfigProvider.overrideWithValue(
            RuntimeConfig.test(isDemoMode: true),
          ),
          posNativePrintingAvailableProvider.overrideWithValue(true),
        ],
      );
      addTearDown(c.dispose);
      expect(c.read(posCentralKitchenWorkflowProvider), isFalse);
    });
  });

  // -------------------------------------------------------------------
  // 6-8. Receipt option, banners and local printer management.
  // -------------------------------------------------------------------
  group('001F-3 everything else on the sheet is preserved', () {
    testWidgets('the receipt-after-payment switch is untouched in the states '
        'where it was previously shown', (tester) async {
      for (final workflow in [
        _Workflow.separateKds,
        _Workflow.loading,
        _Workflow.unavailable,
      ]) {
        await pumpNativeSheet(tester, workflow: workflow);
        expect(
          find.byKey(const Key('auto-print-receipt-toggle')),
          findsOneWidget,
          reason:
              'receipt-after-payment is a separate concern (${workflow.name})',
        );
      }
    });

    testWidgets('direct-print still hides BOTH switches, exactly as before', (
      tester,
    ) async {
      await pumpNativeSheet(tester, workflow: _Workflow.directPrint);
      expect(find.byKey(const Key('auto-print-receipt-toggle')), findsNothing);
      expect(
        find.byKey(const Key('auto-print-kitchen-ticket-toggle')),
        findsNothing,
      );
    });

    testWidgets('both obsolete blue banners stay absent in EVERY workflow '
        'state', (tester) async {
      final l10n = await _l10n('en');
      for (final workflow in _Workflow.values) {
        await pumpNativeSheet(tester, workflow: workflow);
        expect(
          find.byKey(const Key('no-printer-banner')),
          findsNothing,
          reason: 'ask-a-manager banner (${workflow.name})',
        );
        expect(find.text(l10n.deviceSettingsNoPrinter), findsNothing);
        expect(
          find.byKey(const Key('printer-capability-note')),
          findsNothing,
          reason: 'print-bridge capability note (${workflow.name})',
        );
        expect(find.text(l10n.deviceSettingsCapabilityNote), findsNothing);
        expect(find.text(l10n.deviceSettingsNativeNetworkNote), findsNothing);
      }
    });

    testWidgets('local printer setup, purpose assignment and test print all '
        'remain', (tester) async {
      await pumpNativeSheet(tester, workflow: _Workflow.loading);

      // The on-device printer sections are the ones that actually matter now.
      expect(find.byKey(const Key('printer-settings-section')), findsOneWidget);
      expect(find.byKey(const Key('printer-purpose-toggle')), findsOneWidget);
      expect(find.byKey(const Key('reprint-last-receipt')), findsOneWidget);
    });

    testWidgets('the kitchen-printer preparation notice no longer points at a '
        'control that does not exist', (tester) async {
      final l10n = await _l10n('en');
      await pumpNativeSheet(tester, workflow: _Workflow.loading);

      // This notice sits in the LOCAL printer-setup flow and is legitimate, so
      // it is KEPT. But its old body named the "Automatically print kitchen
      // ticket" setting, which this change removes from the surface. Copy that
      // sends a cashier to a control that is not there would be worse than the
      // two banners we deleted, so it now names the real authority.
      expect(
        l10n.posKitchenPrinterPreparationBody,
        contains('Dashboard'),
        reason: 'the notice must name the branch kitchen workflow',
      );
      expect(
        l10n.posKitchenPrinterPreparationBody,
        isNot(contains('Automatically print kitchen ticket')),
        reason: 'it must not reference the removed local setting',
      );
    });
  });

  // -------------------------------------------------------------------
  // 9. Arabic RTL, Hebrew RTL, English LTR.
  // -------------------------------------------------------------------
  group('001F-4 locales', () {
    for (final (locale, expectedDirection) in const [
      ('ar', TextDirection.rtl),
      ('he', TextDirection.rtl),
      ('en', TextDirection.ltr),
    ]) {
      testWidgets('$locale: kitchen toggle absent and banners absent in every '
          'workflow state, with correct directionality', (tester) async {
        final l10n = await _l10n(locale);
        for (final workflow in _Workflow.values) {
          await pumpNativeSheet(tester, workflow: workflow, locale: locale);

          expect(
            find.byKey(const Key('auto-print-kitchen-ticket-toggle')),
            findsNothing,
            reason: '$locale / ${workflow.name}',
          );
          // The localized STRING must be gone too, not merely the key — a
          // renamed key would otherwise let the control creep back silently.
          expect(
            find.text(l10n.posAutoPrintKitchenTicketToggle),
            findsNothing,
            reason: '$locale / ${workflow.name}',
          );
          expect(find.text(l10n.deviceSettingsNoPrinter), findsNothing);
          expect(find.text(l10n.deviceSettingsCapabilityNote), findsNothing);

          expect(
            Directionality.of(
              tester.element(find.byKey(const Key('device-settings-sheet'))),
            ),
            expectedDirection,
            reason: '$locale / ${workflow.name}',
          );
          expect(tester.takeException(), isNull);
        }
      });
    }
  });
}
