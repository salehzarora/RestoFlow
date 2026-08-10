/// SHARED-ADMIN-DEVICE-ACTIONS-RESPONSIVE-001 — the device card's action row at
/// narrow widths.
///
/// THE DEFECT. The row held two intrinsically-sized buttons — the danger-ghost
/// "Revoke" and whichever single lifecycle action the device's status offers —
/// inside a `Row(mainAxisAlignment: end)`. `mainAxisAlignment` decides where
/// spare space goes; it does nothing when there is none, and neither child was
/// flexible. Below roughly 540px the pair wanted more than the card could give
/// and the row overflowed, painting the striped bar over — or pushing off the
/// card entirely — a control that revokes a paired device.
///
/// WHY IT SURVIVED, AND HOW THESE TESTS SEE IT.
///
/// Every existing admin screen test mounts at 1200px, where there is room to
/// spare, so nothing in the suite drove a narrow viewport. That alone explains
/// the miss — but the second half is the part worth writing down: a RenderFlex
/// overflow is reported during PAINT through [FlutterError.onError], and in this
/// harness it does NOT surface through `tester.takeException()`, which returns
/// null while the renderer is dumping "overflowed by 52 pixels" to the console.
/// A test built on `takeException` would therefore be GREEN on a screen that is
/// visibly broken — an assertion that cannot fail is worse than no assertion,
/// because it reads as coverage. These install their own error handler instead,
/// which is the channel the overflow actually travels down.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_feature_admin/restoflow_feature_admin.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';

/// A store whose devices sit in the statuses that actually PRODUCE the widest
/// action rows: `active` and `pending` carry revoke PLUS a lifecycle action,
/// which is the two-button case that overflows. `none` carries the lifecycle
/// action alone (a revoked-or-unpaired device has no pairing to revoke), and is
/// included so the single-button case is covered too.
class _WidestActionsStore extends DemoAdminStore {
  _WidestActionsStore() : super(scope: AdminScope.demo);

  @override
  Future<AdminResult<List<AdminDevice>>> loadDevices() async => Success(const [
    AdminDevice(
      id: 'd-none',
      label: 'Counter POS',
      deviceType: 'pos',
      branchLabel: 'Main branch',
      status: DeviceLifecycleStatus.none,
    ),
    AdminDevice(
      id: 'd-active',
      label: 'Kitchen display',
      deviceType: 'kds',
      branchLabel: 'Main branch',
      status: DeviceLifecycleStatus.active,
    ),
    AdminDevice(
      id: 'd-pending',
      label: 'Bar POS',
      deviceType: 'pos',
      branchLabel: 'Main branch',
      status: DeviceLifecycleStatus.pending,
    ),
  ]);
}

/// Pumps the shared Devices screen at [width] and returns every RenderFlex
/// overflow the renderer reported while doing so.
Future<List<String>> _pumpDevices(
  WidgetTester tester, {
  required double width,
  Locale locale = const Locale('en'),
  double scale = 1.0,
  double height = 3000,
}) async {
  final overflows = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    final text = details.exceptionAsString();
    if (text.contains('overflowed')) {
      overflows.add(text.split('\n').first.trim());
    } else {
      previous?.call(details);
    }
  };

  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  const scope = AdminScope.demo;
  await tester.pumpWidget(
    ProviderScope(
      overrides: adminFeatureOverrides(
        scope: scope,
        repository: _WidestActionsStore(),
      ),
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        builder: (context, child) => MediaQuery.withClampedTextScaling(
          minScaleFactor: scale,
          maxScaleFactor: scale,
          child: child!,
        ),
        home: const Scaffold(body: AdminDevicesScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // RESTORE BEFORE RETURNING, never in a tearDown. The test binding asserts
  // that `FlutterError.onError` is its own handler by the time an expectation
  // runs; leaving the override installed turns every later failure in the file
  // into an opaque "did not complete".
  FlutterError.onError = previous;
  return overflows;
}

void main() {
  // The widths the Dashboard actually renders this screen at, plus 540 — the
  // width the standalone screen tripped over during the V2.2 audit.
  const widths = [390.0, 420.0, 430.0, 540.0];
  const locales = [Locale('en'), Locale('ar')];

  group('A. no horizontal overflow at any narrow width', () {
    for (final width in widths) {
      for (final locale in locales) {
        testWidgets('${width.toInt()}px · ${locale.languageCode}', (
          tester,
        ) async {
          final overflows = await _pumpDevices(
            tester,
            width: width,
            locale: locale,
          );
          expect(
            overflows,
            isEmpty,
            reason: 'device actions must reflow, never clip',
          );
        });
      }
    }
  });

  group('B. no overflow at 2x text scale', () {
    for (final width in [390.0, 430.0, 540.0]) {
      for (final locale in locales) {
        testWidgets('${width.toInt()}px · ${locale.languageCode} · 2x', (
          tester,
        ) async {
          final overflows = await _pumpDevices(
            tester,
            width: width,
            locale: locale,
            scale: 2.0,
            // A doubled text scale needs a taller surface for three cards.
            height: 6000,
          );
          expect(overflows, isEmpty);
        });
      }
    }
  });

  group('C. every action survives the reflow', () {
    testWidgets('all controls are still rendered at 390px', (tester) async {
      await _pumpDevices(tester, width: 390);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // Revoke is offered for the two devices that HAVE a pairing to revoke;
      // a `none` device has none, which is existing behaviour and must stay.
      expect(find.text(l10n.adminRevoke), findsNWidgets(2));
      // One lifecycle action per device, matching its status — no extras.
      expect(find.text(l10n.adminIssueCode), findsOneWidget); // none
      expect(find.text(l10n.adminStartSession), findsOneWidget); // active
      expect(find.text(l10n.adminApprove), findsOneWidget); // pending
    });

    /// The card holding [text], as a rect. The action row is aligned inside its
    /// own card, so the card is the frame the alignment claim is about.
    Rect cardOf(WidgetTester tester, Finder text) => tester.getRect(
      find.ancestor(of: text, matching: find.byType(Card)).first,
    );

    testWidgets('the actions stay at the reading END of the card (LTR)', (
      tester,
    ) async {
      // Wide enough that both controls share one line, so "order" and
      // "alignment" are real horizontal questions rather than vertical ones.
      await _pumpDevices(tester, width: 540);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      final revokeText = find.text(l10n.adminRevoke).first;
      final revoke = tester.getRect(revokeText);
      final start = tester.getRect(find.text(l10n.adminStartSession));
      final card = cardOf(tester, revokeText);

      expect(
        revoke.center.dx,
        lessThan(start.center.dx),
        reason: 'LTR: revoke stays before the lifecycle action',
      );
      // Trailing-aligned: the last control hugs the card's trailing edge far
      // more closely than its leading edge.
      expect(
        card.right - start.right,
        lessThan(start.left - card.left),
        reason: 'the row must sit at the reading end, not float centred',
      );
    });

    testWidgets('RTL mirrors the row without reordering it', (tester) async {
      await _pumpDevices(tester, width: 540, locale: const Locale('ar'));
      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));

      final revokeText = find.text(l10n.adminRevoke).first;
      final revoke = tester.getRect(revokeText);
      final start = tester.getRect(find.text(l10n.adminStartSession));
      final card = cardOf(tester, revokeText);

      expect(
        revoke.center.dx,
        greaterThan(start.center.dx),
        reason: 'RTL: the same order, mirrored — revoke nearer the start edge',
      );
      expect(
        start.left - card.left,
        lessThan(card.right - start.right),
        reason: 'the reading end is the LEFT edge under RTL',
      );
    });

    testWidgets('the actions are still WIRED after the reflow', (tester) async {
      await _pumpDevices(tester, width: 390);
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // Revoke opens its confirmation dialog — proof the callback survived the
      // layout change, without mutating anything.
      await tester.tap(find.text(l10n.adminRevoke).first);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text(l10n.adminCancel));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
