// REAL-MODE-ENTRY-SURFACE-SMOKE-001 — durable coverage for the KDS real-mode
// entry surface (the device-pairing gate).
//
// WHY THIS FILE EXISTS. Every browser smoke in the V0-V6 visual program ran a
// DEMO-mode bundle, and demo mode boots straight past pairing. The pairing gate
// is therefore a surface the whole responsive program never looked at — the
// same blind spot that let an Arabic clip reach production on the Dashboard
// auth gate (DASHBOARD-AUTH-SEGMENTED-AR-CLIP-001). This is the standing
// coverage for the KDS half; it mirrors the POS file deliberately, because the
// two gates share the same DevicePairingScreen composition and must not drift.
//
// SAFETY. Nothing here can touch a backend. The gate is mounted with a stub
// [DevicePairingRepository] that only ever returns a failure, so no device is
// enrolled, no code is redeemed and no remote state is written; the test
// asserts the stub was never even CALLED during render, and that the paired
// child never appears. A plain pairing repository (not a [DeviceSessionManager])
// also means the gate performs no restore, so there is no network read on
// mount. No Supabase client, URL or key is referenced anywhere in this file.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restoflow_auth_identity/restoflow_auth_identity.dart';
import 'package:restoflow_core/restoflow_core.dart';
import 'package:restoflow_l10n/restoflow_l10n.dart';
import 'package:restoflow_kds/src/kds_pairing_gate.dart';

/// A pairing seam that can never succeed and records every call.
///
/// Deliberately NOT a [DeviceSessionManager]: the gate only attempts a session
/// restore when its repository is one, so this keeps the mount completely free
/// of any read.
class _NeverPairsRepository implements DevicePairingRepository {
  int calls = 0;
  final codes = <String>[];

  @override
  Future<Result<DeviceContext, PairingFailure>> pairWithCode({
    required String code,
    required String deviceType,
  }) async {
    calls++;
    codes.add(code);
    return const Failure(PairingFailure(PairingFailureKind.invalidCode));
  }
}

/// The text that would only ever appear on the far side of a real pairing.
const _pairedMarker = 'PAIRED-SURFACE-MUST-NOT-APPEAR';

Future<AppLocalizations> _pumpGate(
  WidgetTester tester, {
  required String language,
  required Size size,
  double textScale = 1.0,
  _NeverPairsRepository? repository,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: Locale(language),
        localizationsDelegates: restoflowLocalizationsDelegates,
        supportedLocales: kSupportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        // The REAL gate, not a stand-in for it.
        home: KdsPairingGate(
          repository: repository ?? _NeverPairsRepository(),
          signedInChild: const Text(_pairedMarker),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return AppLocalizations.delegate.load(Locale(language));
}

/// Paint-time overflow never reaches [WidgetTester.takeException]; the handler
/// is restored BEFORE returning so the caller's `expect` runs with the
/// binding's own handler back in place.
Future<List<String>> _overflowsDuring(Future<void> Function() body) async {
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
  await body();
  FlutterError.onError = previous;
  return overflows;
}

const _codeField = Key('pairing-code');
const _submit = Key('pairing-submit');

/// Desktop, the shipped phone width, and the narrow phone that first exposed
/// the Dashboard clip.
const _widths = <String, Size>{
  '1280': Size(1280, 900),
  '430': Size(430, 932),
  '390': Size(390, 844),
};

const _languages = ['ar', 'he', 'en'];

void main() {
  group('A. the KDS pairing gate actually renders', () {
    for (final language in _languages) {
      for (final entry in _widths.entries) {
        testWidgets('$language @ ${entry.key} shows the pairing surface', (
          tester,
        ) async {
          final l10n = await _pumpGate(
            tester,
            language: language,
            size: entry.value,
          );

          // Identity: this is the pairing gate, not some fallback view.
          expect(find.text(l10n.pairingTitle), findsOneWidget);
          expect(find.text(l10n.pairingIntro), findsOneWidget);
          expect(find.text(l10n.pairingWhereCode), findsOneWidget);
          expect(find.byKey(_codeField), findsOneWidget);
          expect(find.byKey(_submit), findsOneWidget);
          expect(find.text(l10n.pairingPairAction), findsOneWidget);

          // And emphatically NOT the paired surface.
          expect(find.text(_pairedMarker), findsNothing);
        });
      }
    }

    testWidgets('the gate renders at 2x text', (tester) async {
      final l10n = await _pumpGate(
        tester,
        language: 'ar',
        size: const Size(430, 932),
        textScale: 2.0,
      );
      expect(find.byKey(_codeField), findsOneWidget);
      expect(find.byKey(_submit), findsOneWidget);
      expect(find.text(l10n.pairingTitle), findsOneWidget);
    });
  });

  group('B. the gate reports no overflow', () {
    for (final language in _languages) {
      for (final entry in _widths.entries) {
        testWidgets('$language @ ${entry.key} is overflow-free', (
          tester,
        ) async {
          final overflows = await _overflowsDuring(
            () => _pumpGate(tester, language: language, size: entry.value),
          );
          expect(overflows, isEmpty);
        });
      }
    }

    testWidgets('ar @ 390 is overflow-free at 2x text', (tester) async {
      final overflows = await _overflowsDuring(
        () => _pumpGate(
          tester,
          language: 'ar',
          size: const Size(390, 844),
          textScale: 2.0,
        ),
      );
      expect(overflows, isEmpty);
    });
  });

  group('C. nothing is silently clipped', () {
    // A child laid out larger than the box that paints it is cut WITHOUT any
    // RenderFlex overflow being reported. Group B cannot see that; this can.
    for (final language in _languages) {
      for (final entry in _widths.entries) {
        testWidgets('$language @ ${entry.key} keeps its content inside', (
          tester,
        ) async {
          await _pumpGate(tester, language: language, size: entry.value);

          final button = tester.getRect(find.byKey(_submit));
          final labels = find.descendant(
            of: find.byKey(_submit),
            matching: find.byType(Text),
          );
          expect(labels, findsWidgets);
          for (final element in labels.evaluate()) {
            final label = tester.getRect(find.byWidget(element.widget));
            expect(
              button.inflate(0.5).contains(label.topLeft) &&
                  button.inflate(0.5).contains(label.bottomRight),
              isTrue,
              reason:
                  'The pair action label must fit inside the button that '
                  'paints it. label=$label button=$button',
            );
          }

          // The page scrolls vertically, so only horizontal overrun is a clip.
          final view = entry.value;
          for (final element in find.byType(Text).evaluate()) {
            final rect = tester.getRect(find.byWidget(element.widget));
            expect(
              rect.left >= -0.5 && rect.right <= view.width + 0.5,
              isTrue,
              reason:
                  'Text "${(element.widget as Text).data}" runs outside the '
                  '${view.width.toInt()}px viewport: $rect',
            );
          }
          // A paragraph squeezed by a fixed-height ancestor REPORTS the
          // squeezed size — `getRect` and `getSize` both hand back the clamped
          // box, so comparing rects can never see the cut. The text is
          // therefore re-measured independently: what it needs at the width it
          // was actually given, against the height it was actually allowed.
          for (final paragraph in tester.renderObjectList<RenderParagraph>(
            find.byType(Text),
          )) {
            final painter = TextPainter(
              text: paragraph.text,
              textDirection: paragraph.textDirection,
              textScaler: paragraph.textScaler,
              maxLines: paragraph.maxLines,
              textAlign: paragraph.textAlign,
            )..layout(maxWidth: paragraph.size.width);
            expect(
              paragraph.size.height + 0.5,
              greaterThanOrEqualTo(painter.height),
              reason:
                  'Text "${paragraph.text.toPlainText()}" was given '
                  '${paragraph.size.height}px but needs ${painter.height}px at '
                  '${paragraph.size.width}px wide — the difference is cut off '
                  'with no overflow error.',
            );
          }
        });
      }
    }
  });

  group('D. the gate stays operable', () {
    testWidgets('the pair action keeps a usable touch target', (tester) async {
      await _pumpGate(tester, language: 'ar', size: const Size(390, 844));
      final button = tester.getRect(find.byKey(_submit));
      expect(
        button.height,
        greaterThanOrEqualTo(48.0),
        reason:
            'The pair action is the only way off this screen; it must stay a '
            'comfortable target on the narrowest phone.',
      );
    });

    testWidgets('the code field accepts input and validates when empty', (
      tester,
    ) async {
      final repository = _NeverPairsRepository();
      final l10n = await _pumpGate(
        tester,
        language: 'ar',
        size: const Size(430, 932),
        repository: repository,
      );

      // Submitting an empty code must be refused LOCALLY — it must never reach
      // the repository.
      await tester.tap(find.byKey(_submit));
      await tester.pumpAndSettle();
      expect(find.text(l10n.pairingCodeRequired), findsOneWidget);
      expect(
        repository.calls,
        0,
        reason: 'An empty code must never be sent anywhere.',
      );

      await tester.enterText(find.byKey(_codeField), 'ABC123');
      await tester.pumpAndSettle();
      expect(find.text('ABC123'), findsOneWidget);
    });

    testWidgets('primary controls carry non-empty semantics', (tester) async {
      final handle = tester.ensureSemantics();
      final l10n = await _pumpGate(
        tester,
        language: 'ar',
        size: const Size(430, 932),
      );

      // getSemanticsData() is the MERGED payload actually handed to the
      // platform. A node's own `label` can legitimately be empty while the
      // merged data carries the text, so reading the wrong one invents defects.
      final field = tester
          .getSemantics(find.byKey(_codeField))
          .getSemanticsData();
      expect(field.label, isNotEmpty);
      expect(field.label, contains(l10n.pairingCodeLabel));

      final submit = tester
          .getSemantics(find.byKey(_submit))
          .getSemanticsData();
      expect(submit.label, isNotEmpty);
      expect(submit.label, contains(l10n.pairingPairAction));

      handle.dispose();
    });

    testWidgets('the surface mirrors correctly per locale', (tester) async {
      for (final (language, expected) in [
        ('ar', TextDirection.rtl),
        ('he', TextDirection.rtl),
        ('en', TextDirection.ltr),
      ]) {
        await _pumpGate(tester, language: language, size: const Size(430, 932));
        expect(
          Directionality.of(tester.element(find.byKey(_submit))),
          expected,
          reason: '$language must render $expected.',
        );
      }
    });
  });

  group('E. the gate never touches a backend', () {
    testWidgets('rendering redeems nothing and pairs nothing', (tester) async {
      final repository = _NeverPairsRepository();
      await _pumpGate(
        tester,
        language: 'ar',
        size: const Size(430, 932),
        repository: repository,
      );
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(
        repository.calls,
        0,
        reason:
            'Mounting the gate must never redeem a code. A prefilled code is '
            'confirmed by the operator, never auto-submitted (LIVE-DEVICE-001).',
      );
      expect(
        find.text(_pairedMarker),
        findsNothing,
        reason: 'The paired surface must never appear without a real pairing.',
      );
    });

    testWidgets('the kitchen entry surface stays money-free (T-003)', (
      tester,
    ) async {
      for (final language in _languages) {
        await _pumpGate(tester, language: language, size: const Size(430, 932));
        final rendered = tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? '')
            .join(' ');
        expect(
          RegExp(r'[₪$€£]|\d+\.\d{2}').hasMatch(rendered),
          isFalse,
          reason:
              'No money may ever reach a kitchen surface — including the '
              'screen shown before the device is even paired. Rendered: '
              '$rendered',
        );
      }
    });

    testWidgets('a rejected code leaves the operator on the gate', (
      tester,
    ) async {
      final repository = _NeverPairsRepository();
      final l10n = await _pumpGate(
        tester,
        language: 'ar',
        size: const Size(430, 932),
        repository: repository,
      );

      await tester.enterText(find.byKey(_codeField), 'WRONG1');
      await tester.tap(find.byKey(_submit));
      await tester.pumpAndSettle();

      expect(repository.calls, 1);
      expect(repository.codes.single, 'WRONG1');
      // Fails closed: still on the gate, with an honest localized error.
      expect(find.text(_pairedMarker), findsNothing);
      expect(find.byKey(_codeField), findsOneWidget);
      expect(find.text(l10n.pairingInvalidCode), findsOneWidget);
    });
  });
}
